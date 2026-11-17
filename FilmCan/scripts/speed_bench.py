#!/usr/bin/env python3
"""FilmCan speed bench orchestrator (macOS runner). MEASUREMENT ONLY.

Builds nothing itself: it receives two DerivedData folders (ref A and ref B, each built
with `xcodebuild build-for-testing`, both containing FilmCanTests/SpeedBenchTests) and
drives them against disk images made with hdiutil.

  speed_bench.py run   --a-dir WT_A --b-dir WT_B --a-dd DD_A --b-dd DD_B \
                       --ref-a SHA --ref-b SHA --reps 5 --dataset card --out OUT
  speed_bench.py report --json OUT/bench.json [--summary FILE]

Runs alternate A, B, A, B... inside each (dataset, destination) cell; cp / ditto / floor
run once per repetition after the pair. Numbers are only comparable inside one job.
"""
import argparse, json, os, plistlib, re, shutil, statistics, subprocess, sys, time

MB = 1024 * 1024
GB = 1024 * MB

# name -> list of (file count, file size) at full scale
DATASETS = {
    "card":  [(80, 150 * MB)],
    "small": [(5000, 1 * MB)],
    "mix":   [(20, 150 * MB), (1500, 1 * MB), (10, 50 * MB)],
}
# label, hdiutil -fs, requiresFullFsync (what the app sets: exFAT -> true; internal APFS/HFS+ -> false)
DESTS = {
    "exfat": ("ExFAT", "ExFAT", True),
    "apfs":  ("APFS", "APFS", False),
    "hfsx":  ("Mac OS Extended (journaled)", "HFS+J", False),
}
ENGINE_MODES = "fast,paranoid,off"
TOOL_MODES = "cp,ditto,floor"


def sh(cmd, check=True, **kw):
    return subprocess.run(cmd, check=check, text=True, capture_output=True, **kw)


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


# ---------------------------------------------------------------- disks

class Disk:
    def __init__(self, image, volname, fs, size_bytes):
        self.image, self.volname, self.fs, self.size = image, volname, fs, size_bytes
        self.dev = None
        self.mount = None

    def create(self):
        sh(["hdiutil", "create", "-quiet", "-type", "SPARSE", "-size", f"{self.size // MB}m",
            "-fs", self.fs, "-volname", self.volname, self.image])
        out = sh(["hdiutil", "attach", "-nobrowse", "-noverify", "-plist", self.image]).stdout
        for ent in plistlib.loads(out.encode())["system-entities"]:
            if ent.get("mount-point"):
                self.mount = ent["mount-point"]
                self.dev = ent["dev-entry"]
        if not self.mount:
            raise RuntimeError(f"no mount point for {self.image}")
        open(os.path.join(self.mount, ".metadata_never_index"), "w").close()
        sh(["sudo", "-n", "mdutil", "-i", "off", self.mount], check=False)
        return self

    def destroy(self):
        if self.dev:
            sh(["hdiutil", "detach", "-quiet", "-force", self.dev], check=False)
        try:
            os.remove(self.image)
        except OSError:
            pass


def populate(root, spec, seed_pool):
    """Distinct files cheaply: each file starts at a different offset of one random pool."""
    os.makedirs(root, exist_ok=True)
    n = 0
    plen = len(seed_pool)
    for count, size in spec:
        for i in range(count):
            n += 1
            off = (n * 7919 * 4096) % plen
            with open(os.path.join(root, f"C{n:05d}.MXF"), "wb") as f:
                header = n.to_bytes(8, "big") * 512  # 4 KiB, unique per file
                f.write(header)
                left = size - len(header)
                while left > 0:
                    chunk = min(left, plen - off)
                    f.write(seed_pool[off:off + chunk])
                    left -= chunk
                    off = 0
    return n


def scale_spec(name, budget_bytes):
    spec = DATASETS[name]
    full = sum(c * s for c, s in spec)
    k = min(1.0, budget_bytes / full)
    scaled = [(max(1, int(c * k)), s) for c, s in spec]
    return scaled, full, sum(c * s for c, s in scaled), k


# ---------------------------------------------------------------- xcodebuild

def run_invocation(dd, proj, env, logfile):
    cmd = ["xcodebuild", "test-without-building", "-project", proj, "-scheme", "FilmCan",
           "-destination", "platform=macOS", "-derivedDataPath", dd,
           "-only-testing:FilmCanTests/SpeedBenchTests/test_bench", "-parallel-testing-enabled", "NO"]
    e = dict(os.environ)
    for k, v in env.items():
        e["TEST_RUNNER_" + k] = v
    with open(logfile, "w") as lf:
        r = subprocess.run(cmd, env=e, stdout=lf, stderr=subprocess.STDOUT, text=True)
    return r.returncode


# ---------------------------------------------------------------- run

def cmd_run(a):
    os.makedirs(os.path.join(a.out, "raw"), exist_ok=True)
    os.makedirs(os.path.join(a.out, "logs"), exist_ok=True)
    work = os.environ.get("RUNNER_TEMP", "/tmp") + "/speedbench-disks"
    os.makedirs(work, exist_ok=True)
    started = time.time()

    free = shutil.disk_usage(work).free
    # Peak use is source image + one destination image, each ~1.15x the dataset, plus slack.
    budget = max(0, int((free * 0.7 - 1 * GB) / 2.4))
    meta = {
        "ref_a": a.ref_a, "ref_b": a.ref_b, "reps": a.reps, "dataset": a.dataset,
        "free_disk_bytes_before_datasets": free, "dataset_budget_bytes": budget,
        "sw_vers": sh(["sw_vers"], check=False).stdout.strip(),
        "cpu": sh(["sysctl", "-n", "machdep.cpu.brand_string"], check=False).stdout.strip(),
        "ncpu": os.cpu_count(),
        "ram_bytes": sh(["sysctl", "-n", "hw.memsize"], check=False).stdout.strip(),
        "df": sh(["df", "-h", work], check=False).stdout,
        "datasets": {}, "cells": [],
    }
    log("df:\n" + meta["df"])
    names = list(DATASETS) if a.dataset == "all" else [a.dataset]
    dests = [d.strip() for d in a.dests.split(",") if d.strip()]
    pool = os.urandom(32 * MB)
    refs = [("A", a.a_dir, a.a_dd), ("B", a.b_dir, a.b_dd)]
    failures = 0

    for ds in names:
        spec, full, used, k = scale_spec(ds, budget)
        meta["datasets"][ds] = {"full_bytes": full, "used_bytes": used, "scale": k, "spec": spec}
        if used < 100 * MB:
            log(f"skip dataset {ds}: only {used} bytes fit")
            continue
        log(f"dataset {ds}: {used / GB:.2f} GB (scale {k:.2f} of {full / GB:.2f} GB)")
        size = int(used * 1.15) + 384 * MB
        src = Disk(f"{work}/src_{ds}.sparseimage", "BENCHSRC", "ExFAT", size).create()
        try:
            root = os.path.join(src.mount, "dataset")
            nfiles = populate(root, spec, pool)
            sh(["sync"])
            log(f"  populated {nfiles} files on {src.mount}")
            for dname in dests:
                label, fs, fsync = DESTS[dname]
                if time.time() - started > a.max_minutes * 60:
                    log(f"  time budget reached, skipping {ds}/{dname}")
                    meta["cells"].append({"dataset": ds, "dest": dname, "skipped": "time budget"})
                    continue
                dst = Disk(f"{work}/dst_{dname}.sparseimage", "BENCHDST", fs, size).create()
                cell = {"dataset": ds, "dest": dname, "dest_label": label, "files": []}
                try:
                    log(f"  dest {dname} at {dst.mount}")
                    for rep in range(1, a.reps + 1):
                        if time.time() - started > a.max_minutes * 60:
                            log("  time budget reached, stopping reps")
                            cell["stopped_after_reps"] = rep - 1
                            break
                        plan = [(lab, d, dd, ENGINE_MODES) for lab, d, dd in refs]   # A, B
                        plan.append(("tools", a.a_dir, a.a_dd, TOOL_MODES))
                        for lab, wt, dd, modes in plan:
                            out_json = f"{a.out}/raw/{ds}_{dname}_{lab}_rep{rep}.json"
                            env = {"FILMCAN_BENCH": "1", "FILMCAN_IO_PERF": "1",
                                   "FILMCAN_BENCH_SRC": root, "FILMCAN_BENCH_DEST": dst.mount,
                                   "FILMCAN_BENCH_OUT": out_json, "FILMCAN_BENCH_LABEL": lab,
                                   "FILMCAN_BENCH_MODES": modes,
                                   "FILMCAN_BENCH_FSYNC": "1" if fsync else "0"}
                            t0 = time.time()
                            rc = run_invocation(dd, f"{wt}/FilmCan/FilmCan.xcodeproj", env,
                                                f"{a.out}/logs/{ds}_{dname}_{lab}_rep{rep}.log")
                            ok = os.path.exists(out_json)
                            log(f"    rep {rep} {lab}: rc={rc} json={'yes' if ok else 'NO'} {time.time() - t0:.0f}s")
                            if not ok:
                                failures += 1
                            else:
                                cell["files"].append(os.path.basename(out_json))
                finally:
                    dst.destroy()
                meta["cells"].append(cell)
        finally:
            src.destroy()

    meta["elapsed_s"] = time.time() - started
    meta["failed_invocations"] = failures
    # fold the raw files in
    raw = {}
    for fn in sorted(os.listdir(f"{a.out}/raw")):
        with open(f"{a.out}/raw/{fn}") as f:
            raw[fn] = json.load(f)
    with open(f"{a.out}/bench.json", "w") as f:
        json.dump({"meta": meta, "raw": raw}, f, indent=1)
    log(f"done in {meta['elapsed_s'] / 60:.1f} min, failed invocations: {failures}")
    return 0 if failures == 0 else 1


# ---------------------------------------------------------------- report

def med(xs):
    return statistics.median(xs) if xs else float("nan")


def collect(doc):
    """{(dataset, dest): {(label, mode): [rows]}} where row = dict(wall, perf, valid)."""
    out = {}
    for fn, j in doc["raw"].items():
        m = re.match(r"(.+?)_(.+?)_(A|B|tools)_rep(\d+)\.json$", fn)
        if not m:
            continue
        ds, dest, lab = m.group(1), m.group(2), m.group(3)
        cell = out.setdefault((ds, dest), {"info": j, "g": {}})
        cell["info"] = j
        for r in j["runs"]:
            key = (lab, r["mode"])
            cell["g"].setdefault(key, []).append(r)
    return out


def bucket_sum(rows, bucket):
    vals = []
    for r in rows:
        tot = 0.0
        for kd in (r.get("perf") or {}).values():
            tot += (kd.get(bucket) or {}).get("seconds", 0.0)
        vals.append(tot)
    return med(vals)


def fmt_group(rows):
    ok = [r["wall_s"] for r in rows if r.get("valid")]
    bad = len(rows) - len(ok)
    if not ok:
        return None
    return {"n": len(ok), "bad": bad, "med": med(ok), "min": min(ok), "max": max(ok),
            "spread": (max(ok) - min(ok)) / med(ok) * 100 if med(ok) else 0.0}


def build_report(doc, ref_a, ref_b):
    meta = doc["meta"]
    L = []
    L.append("# Banc de vitesse FilmCan — A/B\n")
    L.append(f"**A** = `{ref_a}`  ·  **B** = `{ref_b}`  ·  répétitions demandées : {meta['reps']}  ·  "
             f"durée du banc : {meta.get('elapsed_s', 0) / 60:.0f} min\n")
    L.append("> Runner GitHub : machine virtuelle partagée, disques = images disque sur le même SSD "
             "virtuel. Aucun de ces chiffres n'est la vitesse d'un vrai disque. Seule compte la comparaison "
             "relative A/B dans ce job, et seulement quand les plages [min–max] ne se chevauchent pas.\n")
    L.append(f"Machine : {meta.get('cpu', '?')} · {meta.get('ncpu', '?')} cœurs · "
             f"disque libre avant jeux de données : {meta['free_disk_bytes_before_datasets'] / GB:.1f} Go · "
             f"budget jeu de données : {meta['dataset_budget_bytes'] / GB:.1f} Go\n")
    for ds, d in meta["datasets"].items():
        note = "" if d["scale"] >= 0.999 else f" — **réduit à {d['scale'] * 100:.0f} %** (espace disque du runner)"
        L.append(f"- jeu `{ds}` : {d['used_bytes'] / GB:.2f} Go sur {d['full_bytes'] / GB:.2f} Go prévus{note}")
    L.append("")
    cells = collect(doc)
    for (ds, dest), cell in sorted(cells.items()):
        info = cell["info"]
        di = info["dest"]
        L.append(f"## {ds} → {dest}\n")
        L.append(f"{info['files']} fichiers, {info['bytes'] / GB:.2f} Go · `requiresFullFsync={info['requiresFullFsync']}` · "
                 f"classe moteur détectée : `{di['engineClass']}` (verifyRunAheadFiles={di['verifyRunAheadFiles']}, "
                 f"chunk {di['chunkBytes'] // MB} Mo) · isSSD={di['isSSD']} bus={di['bus']}\n")
        L.append("| Mode | A médiane (s) | A min–max | B médiane (s) | B min–max | B vs A | Bruit (spread) | Verdict |")
        L.append("|---|---|---|---|---|---|---|---|")
        for mode in ("fast", "paranoid", "off"):
            a = fmt_group(cell["g"].get(("A", mode), []))
            b = fmt_group(cell["g"].get(("B", mode), []))
            if not a or not b:
                L.append(f"| {mode} | — | — | — | — | — | — | données manquantes |")
                continue
            delta = (b["med"] - a["med"]) / a["med"] * 100
            disjoint = b["max"] < a["min"] or a["max"] < b["min"]
            if disjoint:
                verdict = "**B plus rapide**" if b["med"] < a["med"] else "**A plus rapide**"
            else:
                verdict = "indiscernable (plages qui se chevauchent)"
            L.append(f"| {mode} | {a['med']:.1f} | {a['min']:.1f}–{a['max']:.1f} (n={a['n']}) | "
                     f"{b['med']:.1f} | {b['min']:.1f}–{b['max']:.1f} (n={b['n']}) | {delta:+.1f} % | "
                     f"A {a['spread']:.0f} % / B {b['spread']:.0f} % | {verdict} |")
        L.append("")
        L.append("Références (indépendantes de A/B) :\n")
        L.append("| Référence | médiane (s) | min–max | Fast A / réf. | Fast B / réf. |")
        L.append("|---|---|---|---|---|")
        fa = fmt_group(cell["g"].get(("A", "fast"), []))
        fb = fmt_group(cell["g"].get(("B", "fast"), []))
        for tool, name in (("cp", "cp -R"), ("ditto", "ditto"), ("floor", "plancher (copie + 1 relecture)")):
            t = fmt_group(cell["g"].get(("tools", tool), []))
            if not t:
                L.append(f"| {name} | — | — | — | — |")
                continue
            ra = f"{fa['med'] / t['med']:.2f}×" if fa else "—"
            rb = f"{fb['med'] / t['med']:.2f}×" if fb else "—"
            L.append(f"| {name} | {t['med']:.1f} | {t['min']:.1f}–{t['max']:.1f} (n={t['n']}) | {ra} | {rb} |")
        L.append("")
        L.append("Détail par étape (FILMCAN_IO_PERF, médiane en s, somme des destinations ; les étapes se chevauchent, "
                 "leur somme dépasse le mur) :\n")
        buckets = ["source read", "dest write", "cache flush", "verify re-read", "settle sleep"]
        L.append("| Run | " + " | ".join(buckets) + " |")
        L.append("|---|" + "---|" * len(buckets))
        for lab in ("A", "B"):
            for mode in ("fast", "paranoid", "off"):
                rows = [r for r in cell["g"].get((lab, mode), []) if r.get("valid")]
                if not rows:
                    continue
                L.append(f"| {lab} {mode} | " + " | ".join(f"{bucket_sum(rows, b):.2f}" for b in buckets) + " |")
        L.append("")
        purged = [r.get("purged") for rows in cell["g"].values() for r in rows]
        L.append(f"Purge du cache avant chaque run : {sum(1 for p in purged if p)}/{len(purged)} réussies.\n")
        bad = sum(1 for rows in cell["g"].values() for r in rows if not r.get("valid"))
        if bad:
            L.append(f"⚠️ {bad} run(s) invalides (octets manquants ou erreur moteur), exclus des médianes.\n")
    for c in meta["cells"]:
        if c.get("skipped"):
            L.append(f"⚠️ cellule `{c['dataset']}/{c['dest']}` non mesurée : {c['skipped']}")
        if c.get("stopped_after_reps") is not None:
            L.append(f"⚠️ cellule `{c['dataset']}/{c['dest']}` arrêtée après {c['stopped_after_reps']} répétition(s) (budget de temps)")
    if meta.get("failed_invocations"):
        L.append(f"\n⚠️ {meta['failed_invocations']} invocation(s) xcodebuild sans résultat (voir logs de l'artefact).")
    return "\n".join(L) + "\n"


def cmd_report(a):
    with open(a.json) as f:
        doc = json.load(f)
    text = build_report(doc, doc["meta"]["ref_a"], doc["meta"]["ref_b"])
    if a.summary:
        with open(a.summary, "a") as f:
            f.write(text)
    print(text)
    return 0


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--a-dir", required=True); r.add_argument("--b-dir", required=True)
    r.add_argument("--a-dd", required=True); r.add_argument("--b-dd", required=True)
    r.add_argument("--ref-a", required=True); r.add_argument("--ref-b", required=True)
    r.add_argument("--reps", type=int, default=5)
    r.add_argument("--dataset", default="card", choices=list(DATASETS) + ["all"])
    r.add_argument("--dests", default="exfat,apfs,hfsx")
    r.add_argument("--max-minutes", type=float, default=300)
    r.add_argument("--out", required=True)
    q = sub.add_parser("report")
    q.add_argument("--json", required=True); q.add_argument("--summary")
    a = p.parse_args()
    sys.exit(cmd_run(a) if a.cmd == "run" else cmd_report(a))


if __name__ == "__main__":
    main()
