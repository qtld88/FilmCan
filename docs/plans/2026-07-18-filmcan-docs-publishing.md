# FilmCan Docs Publishing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a curated ~21-page subset of `docs/` as Kodak-themed HTML pages on the FilmCan website, built at deploy time from the existing markdown.

**Architecture:** A Python build script (`scripts/build_docs.py`) renders an explicit allowlist of markdown files to themed HTML under `website/docs/` (gitignored output). Each page wraps the rendered body in a shared template: the site's top nav plus a grouped left sidebar. All internal doc links use root-absolute `/docs/...` URLs. The GitHub Actions Pages workflow runs the script before uploading the `website/` artifact, so a push to `main` redeploys both site and docs.

**Tech Stack:** Python 3 + `markdown` library (extensions: tables, fenced_code, toc, sane_lists); existing static HTML/CSS site; GitHub Actions Pages deploy.

Spec: `docs/specs/2026-07-18-filmcan-docs-publishing-design.md`

---

## File structure

- Create `scripts/build_docs.py` — the whole build: allowlist, markdown render, link rewrite + integrity check, sidebar, template, em-dash guard.
- Create `website/docs.css` — docs-only layout + prose styling, reuses `styles.css` theme tokens.
- Modify `docs/features/copy-engines.md` — remove rsync history.
- Modify `docs/index.md` — rewrite to link only published pages.
- Modify `docs/faq.md`, `docs/privacy.md`, `docs/troubleshooting.md` — repoint links to excluded pages.
- Modify (em-dash normalization) the allowlisted `.md` files that contain `—`.
- Modify `website/index.html` — activate the reserved Docs nav slot.
- Modify `.github/workflows/deploy-pages.yml` — add the build step + trigger paths.
- Modify `.gitignore` — ignore `website/docs/`.

Generated output `website/docs/**.html` is never committed.

---

### Task 1: Content cleanups in canonical markdown

**Files:**
- Modify: `docs/features/copy-engines.md:8-12`
- Modify: `docs/index.md` (full rewrite)
- Modify: `docs/faq.md:80`, `docs/faq.md:88`
- Modify: `docs/privacy.md:24`
- Modify: `docs/troubleshooting.md:99`

- [ ] **Step 1: Remove the rsync blockquote from copy-engines.md**

In `docs/features/copy-engines.md`, delete the deprecation blockquote and its surrounding blank lines (lines 8-12), so the intro paragraph is followed directly by the `---` separator and `## How it works`. Replace:

```markdown
destination at once, verify with cinema-grade hash lists, and recover a failed
drive with one click.

> **The rsync engine was retired in FilmCan 1.2.** Earlier versions let you pick
> between rsync and the FilmCan Engine. The engine picker is gone and the rsync
> engine has been removed entirely — the FilmCan Engine handles every backup, with
> no Homebrew rsync to install.

---
```

with:

```markdown
destination at once, verify with cinema-grade hash lists, and recover a failed
drive with one click.

---
```

- [ ] **Step 2: Rewrite docs/index.md to published-only links**

Replace the entire contents of `docs/index.md` with:

```markdown
# FilmCan Documentation

---

## Getting started

- [Installation](./installation.md)
- [Quick Start](./quickstart.md)

## Features

- [Features Overview](./features/index.md)
- [Copy Engine](./features/copy-engines.md)
- [Netflix Ingest](./features/netflix-ingest.md)
- [Destination Presets](./features/destination-presets.md)
- [Transfer History](./features/transfer-history.md)
- [Options](./features/options.md)
- [Smart Date](./features/smart-date.md)
- [Multi-Destination](./features/multi-destination.md)
- [Stop & Resume](./features/stop.md)
- [Safe Checks](./features/safe-checks.md)
- [Push Notifications](./features/push-notifications.md)
- [Hash Lists](./features/hash-lists.md)

## Reference

- [Transfer Errors](./reference/transfer-errors.md)

## Help

- [Troubleshooting](./troubleshooting.md)
- [FAQ](./faq.md)

## About

- [Privacy Policy](./privacy.md)
- [AI Usage](./ai-usage.md)
- [Roadmap](./roadmap.md)
```

- [ ] **Step 3: Repoint links to excluded pages**

`docs/faq.md` line 80, replace:

```markdown
See [Contributing](./contributing.md) for bug reporting.
```

with:

```markdown
See [Report a bug](https://github.com/qtld88/FilmCan/issues) for bug reporting.
```

`docs/faq.md` line 88, replace:

```markdown
- [Support](./support.md)
```

with:

```markdown
- [Support](/#support)
```

`docs/privacy.md` line 24, replace:

```markdown
If you have questions, see [Support](./support.md).
```

with:

```markdown
If you have questions, see [Support](/#support).
```

`docs/troubleshooting.md` line 99, replace:

```markdown
- [Report a bug](./contributing.md)
```

with:

```markdown
- [Report a bug](https://github.com/qtld88/FilmCan/issues)
```

- [ ] **Step 4: Normalize em dashes in the allowlisted markdown**

Run this from the repo root. It replaces em dashes (spaced or not) with a comma + space in every allowlisted source file, then reports remaining counts (must all be zero):

```bash
python3 - <<'PY'
import re, pathlib
files = [
 "docs/quickstart.md","docs/installation.md","docs/faq.md","docs/privacy.md",
 "docs/troubleshooting.md","docs/roadmap.md","docs/ai-usage.md","docs/index.md",
 "docs/features/index.md","docs/features/multi-destination.md","docs/features/source-selection.md",
 "docs/features/destination-presets.md","docs/features/hash-lists.md","docs/features/safe-checks.md",
 "docs/features/stop.md","docs/features/transfer-history.md","docs/features/push-notifications.md",
 "docs/features/smart-date.md","docs/features/visualizations.md","docs/features/options.md",
 "docs/features/netflix-ingest.md","docs/features/copy-engines.md","docs/reference/transfer-errors.md",
]
for f in files:
    p = pathlib.Path(f); t = p.read_text(encoding="utf-8")
    t2 = re.sub(r"\s*—\s*", ", ", t)
    if t2 != t: p.write_text(t2, encoding="utf-8")
left = {f: pathlib.Path(f).read_text(encoding="utf-8").count("—") for f in files}
bad = {f:n for f,n in left.items() if n}
print("remaining em dashes:", bad or "none")
PY
```

Expected: `remaining em dashes: none`

- [ ] **Step 5: Eyeball the normalized files**

Run: `git diff docs/features/options.md docs/features/netflix-ingest.md`
Scan for any `, ` replacement that reads badly (e.g. a comma where a colon was clearly meant, or a double comma). Fix those by hand. Most `X, Y` results read fine.

- [ ] **Step 6: Commit**

```bash
git add docs/features/copy-engines.md docs/index.md docs/faq.md docs/privacy.md docs/troubleshooting.md docs/**/*.md
git commit -m "docs: prep content for website publishing

Remove rsync history from copy-engines, rewrite docs index to
published-only links, repoint support/contributing links off excluded
pages, and strip em dashes from the published set."
```

---

### Task 2: Build script `scripts/build_docs.py`

**Files:**
- Create: `scripts/build_docs.py`

- [ ] **Step 1: Write the script**

```python
#!/usr/bin/env python3
"""Render the curated docs allowlist to themed HTML under website/docs/.

Run from anywhere; paths are resolved relative to the repo root.
Exits non-zero on a missing source file, a link to a non-published page,
or a stray em dash in rendered output.
"""
import os
import re
import shutil
import sys
from pathlib import Path

import markdown

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
OUT = ROOT / "website" / "docs"

# (source path relative to docs/, sidebar group or None for the home page, nav title)
PAGES = [
    ("index.md", None, "Overview"),
    ("quickstart.md", "Getting started", "Quick Start"),
    ("installation.md", "Getting started", "Installation"),
    ("features/index.md", "Features", "Features Overview"),
    ("features/multi-destination.md", "Features", "Multi-Destination"),
    ("features/source-selection.md", "Features", "Source Selection"),
    ("features/destination-presets.md", "Features", "Destination Presets"),
    ("features/hash-lists.md", "Features", "Hash Lists"),
    ("features/safe-checks.md", "Features", "Safe Checks"),
    ("features/stop.md", "Features", "Stop & Resume"),
    ("features/transfer-history.md", "Features", "Transfer History"),
    ("features/push-notifications.md", "Features", "Push Notifications"),
    ("features/smart-date.md", "Features", "Smart Date"),
    ("features/visualizations.md", "Features", "Visualizations"),
    ("features/options.md", "Features", "Options"),
    ("features/netflix-ingest.md", "Features", "Netflix Ingest"),
    ("features/copy-engines.md", "Features", "Copy Engine"),
    ("reference/transfer-errors.md", "Reference", "Transfer Errors"),
    ("troubleshooting.md", "Help", "Troubleshooting"),
    ("faq.md", "Help", "FAQ"),
    ("privacy.md", "About", "Privacy"),
    ("ai-usage.md", "About", "AI Usage"),
    ("roadmap.md", "About", "Roadmap"),
]

ALLOWED = {src for src, _, _ in PAGES}
GROUP_ORDER = ["Getting started", "Features", "Reference", "Help", "About"]
TITLES = {src: title for src, _, title in PAGES}

errors = []


def out_path(src):
    return src[:-3] + ".html"  # features/stop.md -> features/stop.html


def rewrite_links(html, src):
    base = os.path.dirname(src)

    def repl(m):
        href = m.group(1)
        if re.match(r"^(https?:|mailto:|#|/)", href):
            return m.group(0)
        frag = ""
        if "#" in href:
            href, frag = href.split("#", 1)
            frag = "#" + frag
        if href.endswith(".md"):
            target = os.path.normpath(os.path.join(base, href)).replace(os.sep, "/")
            if target not in ALLOWED:
                errors.append(f"{src}: links to non-published page: {m.group(1)}")
                return m.group(0)
            return f'href="/docs/{out_path(target)}{frag}"'
        return m.group(0)

    return re.sub(r'href="([^"]+)"', repl, html)


def sidebar(active_src):
    rows = ['<a class="home%s" href="/docs/">Documentation</a>'
            % (" active" if active_src == "index.md" else "")]
    for group in GROUP_ORDER:
        items = [(s, t) for (s, g, t) in PAGES if g == group]
        if not items:
            continue
        rows.append(f'<div class="grp"><span class="grp-t">{group}</span><ul>')
        for s, t in items:
            cls = ' class="active"' if s == active_src else ""
            rows.append(f'<li><a href="/docs/{out_path(s)}"{cls}>{t}</a></li>')
        rows.append("</ul></div>")
    return "\n".join(rows)


NAV = """<nav><div class="wrap">
  <a class="brand" href="/" style="text-decoration:none"><img src="/assets/icon.png" alt="FilmCan icon">FilmCan</a>
  <div class="links">
    <a href="/#how">How it works</a>
    <a href="/#features">Features</a>
    <a href="/docs/" class="active">Docs</a>
    <a href="/#faq">FAQ</a>
    <a href="/#support">Support</a>
    <a class="btn" href="/#download">Download</a>
  </div>
</div></nav>"""

TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · FilmCan Docs</title>
<link rel="icon" href="/assets/favicon.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/styles.css">
<link rel="stylesheet" href="/docs.css">
</head>
<body class="docs">
{nav}
<div class="docs-wrap">
  <input type="checkbox" id="sb-toggle" hidden>
  <label for="sb-toggle" class="sb-btn">Menu</label>
  <aside class="sidebar">{sidebar}</aside>
  <main class="doc">{body}</main>
</div>
</body>
</html>
"""


def build():
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    for src, _, _ in PAGES:
        sp = DOCS / src
        if not sp.exists():
            errors.append(f"missing source: docs/{src}")
            continue
        md = markdown.Markdown(extensions=["tables", "fenced_code", "toc", "sane_lists"])
        body = md.convert(sp.read_text(encoding="utf-8"))
        body = rewrite_links(body, src)
        if "—" in body:
            errors.append(f"{src}: rendered HTML still contains an em dash")
        html = TEMPLATE.format(title=TITLES[src], nav=NAV, sidebar=sidebar(src), body=body)
        dest = OUT / out_path(src)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(html, encoding="utf-8")
    if errors:
        print("BUILD FAILED:", file=sys.stderr)
        for e in errors:
            print("  -", e, file=sys.stderr)
        sys.exit(1)
    print(f"built {len(PAGES)} docs pages into {OUT}")


if __name__ == "__main__":
    build()
```

- [ ] **Step 2: Install the dependency and run the build**

Run:
```bash
pip install markdown
python3 scripts/build_docs.py
```
Expected: `built 23 docs pages into .../website/docs`
If it prints `BUILD FAILED` with a "links to non-published page" line, fix that link in the named source `.md` (repoint to a published page, a `/#anchor`, or an external URL), then re-run until it succeeds.

- [ ] **Step 3: Assert the output set**

Run:
```bash
find website/docs -name '*.html' | wc -l
test -f website/docs/index.html && test -f website/docs/features/netflix-ingest.html && echo OK
grep -rl '—' website/docs && echo "FOUND EM DASH" || echo "no em dash"
```
Expected: `23`, then `OK`, then `no em dash`.

- [ ] **Step 4: Commit**

```bash
git add scripts/build_docs.py
git commit -m "feat(site): add docs build script (md -> themed HTML)"
```

---

### Task 3: Docs stylesheet `website/docs.css`

**Files:**
- Create: `website/docs.css`

- [ ] **Step 1: Write the stylesheet**

Reuses the theme tokens defined in `:root` by `styles.css` (loaded before this file).

```css
/* Docs layout + prose. Theme tokens come from styles.css :root. */
body.docs{padding:0}
.docs-wrap{max-width:var(--maxw);margin:0 auto;padding:0 28px;display:grid;grid-template-columns:230px 1fr;gap:40px;align-items:start}

/* SIDEBAR */
.sidebar{position:sticky;top:88px;font-size:14px;padding:24px 0 40px;max-height:calc(100vh - 100px);overflow-y:auto}
.sidebar .home{display:block;font-weight:700;text-decoration:none;margin-bottom:16px;color:var(--text)}
.sidebar .home.active{color:var(--yellow)}
.sidebar .grp{margin-bottom:18px}
.sidebar .grp-t{display:block;font-size:11px;letter-spacing:1.5px;text-transform:uppercase;color:rgba(244,242,238,.45);font-weight:600;margin-bottom:8px}
.sidebar ul{list-style:none;margin:0;padding:0}
.sidebar li a{display:block;text-decoration:none;color:rgba(244,242,238,.72);padding:5px 10px;border-radius:7px;border-left:2px solid transparent}
.sidebar li a:hover{color:var(--text);background:rgba(244,242,238,.05)}
.sidebar li a.active{color:var(--yellow);border-left-color:var(--yellow);background:rgba(255,201,0,.07)}
.sb-btn{display:none}

/* PROSE */
.doc{padding:34px 0 80px;min-width:0;line-height:1.62}
.doc h1{font-size:34px;font-weight:700;letter-spacing:-.5px;margin:0 0 18px}
.doc h2{font-size:23px;font-weight:700;margin:38px 0 12px}
.doc h3{font-size:18px;font-weight:600;margin:26px 0 8px}
.doc p{margin:0 0 14px;color:rgba(244,242,238,.85)}
.doc ul,.doc ol{margin:0 0 14px 22px;color:rgba(244,242,238,.85)}
.doc li{margin:5px 0}
.doc a{color:var(--yellow);text-decoration:none}
.doc a:hover{text-decoration:underline}
.doc strong{color:var(--text)}
.doc hr{border:none;border-top:1px solid var(--stroke);margin:28px 0}
.doc code{background:rgba(244,242,238,.08);padding:2px 6px;border-radius:5px;font-size:.9em;font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
.doc pre{background:#141414;border:1px solid var(--stroke);border-radius:10px;padding:16px;overflow-x:auto;margin:0 0 16px}
.doc pre code{background:none;padding:0;font-size:13px;line-height:1.5}
.doc blockquote{border-left:3px solid var(--yellow);background:rgba(255,201,0,.06);margin:0 0 16px;padding:12px 16px;border-radius:0 8px 8px 0}
.doc blockquote p:last-child{margin-bottom:0}
.doc table{width:100%;border-collapse:collapse;margin:0 0 18px;font-size:14px;display:block;overflow-x:auto}
.doc th,.doc td{border:1px solid var(--stroke);padding:8px 12px;text-align:left;vertical-align:top}
.doc th{background:rgba(244,242,238,.05);font-weight:600}

@media(max-width:820px){
  .docs-wrap{grid-template-columns:1fr;gap:0}
  .sb-btn{display:inline-block;margin:16px 0 0;cursor:pointer;font-size:13px;font-weight:600;color:var(--yellow);border:1px solid var(--stroke2);border-radius:8px;padding:6px 12px}
  .sidebar{position:static;max-height:none;display:none;padding-top:12px}
  #sb-toggle:checked ~ .sidebar{display:block}
}
```

- [ ] **Step 2: Rebuild and commit**

```bash
python3 scripts/build_docs.py
git add website/docs.css
git commit -m "feat(site): add Kodak-theme docs stylesheet"
```

---

### Task 4: Site integration (nav, workflow, gitignore)

**Files:**
- Modify: `website/index.html:35`
- Modify: `.github/workflows/deploy-pages.yml`
- Modify: `.gitignore`

- [ ] **Step 1: Activate the Docs nav slot**

In `website/index.html`, replace:

```html
    <a href="#support">Support</a>
    <!-- Docs nav slot reserved for phase 2: <a href="docs/">Docs</a> -->
    <a class="btn" href="#download">Download</a>
```

with:

```html
    <a href="#support">Support</a>
    <a href="/docs/">Docs</a>
    <a class="btn" href="#download">Download</a>
```

- [ ] **Step 2: Add the build step to the deploy workflow**

Open `.github/workflows/deploy-pages.yml`. In the `paths:` list under the push trigger, add `docs/**`, `scripts/build_docs.py`, and `website/docs.css` alongside the existing `website/**` entry. Then, in the build job, insert these steps immediately **before** the `actions/upload-pages-artifact` step:

```yaml
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - name: Build docs
        run: |
          pip install markdown
          python scripts/build_docs.py
```

(Keep the existing `actions/upload-pages-artifact` `path: website` unchanged; it now includes the generated `website/docs/`.)

- [ ] **Step 3: Ignore build output**

Append to `.gitignore`:

```
website/docs/
```

- [ ] **Step 4: Verify the nav change is not broken and commit**

Run: `grep -n 'href="/docs/"' website/index.html`
Expected: one match on the nav line.

```bash
git add website/index.html .github/workflows/deploy-pages.yml .gitignore
git commit -m "feat(site): wire docs into nav and Pages deploy"
```

---

### Task 5: Local preview verification

**Files:** none (verification only)

- [ ] **Step 1: Build and serve**

```bash
python3 scripts/build_docs.py
```
Start the local server (via the `site` config in `.claude/launch.json`, port 8125, serving `website/`).

- [ ] **Step 2: Check the docs home and a feature page**

Load `http://localhost:8125/docs/` and `http://localhost:8125/docs/features/netflix-ingest.html`. Confirm via DOM/JS checks:
- The top nav renders with the Docs link marked active.
- The left sidebar lists the five groups (Getting started, Features, Reference, Help, About) with the current page highlighted.
- A code block and a markdown table render inside the Kodak theme (dark bg, yellow accents).
- Internal sidebar links resolve to `/docs/...html` (click one, confirm navigation).

- [ ] **Step 3: Check a link that used to point at an excluded page**

Load `http://localhost:8125/docs/faq.html`. Confirm the "Report a bug" link points to `https://github.com/qtld88/FilmCan/issues` and the "Support" link to `/#support` (root site anchor), not a broken `/docs/...support.html`.

- [ ] **Step 4: Responsive check**

Resize to mobile width. Confirm the sidebar collapses behind the "Menu" toggle and the body does not scroll horizontally (tables/code scroll within their own box).

---

### Task 6: Deploy verification

**Files:** none (verification only)

- [ ] **Step 1: Push and watch the deploy**

```bash
git push origin main
```
Watch the `deploy-pages.yml` run. Confirm the "Build docs" step prints `built 23 docs pages` and the deploy succeeds.

- [ ] **Step 2: Check the live routes**

After the deploy completes, confirm these load with HTTP 200 and rendered docs content:
```bash
for u in / /docs/ /docs/features/netflix-ingest.html /docs/faq.html; do
  echo -n "$u -> "; curl -s -o /dev/null -w '%{http_code}\n' "https://www.filmcan.eu$u"
done
```
Expected: `200` for each.

- [ ] **Step 3: Confirm no excluded page leaked**

```bash
for u in /docs/architecture.html /docs/features/rsync.html /docs/technical-debt.html; do
  echo -n "$u -> "; curl -s -o /dev/null -w '%{http_code}\n' "https://www.filmcan.eu$u"
done
```
Expected: `404` for each.

---

## Self-review notes

- **Spec coverage:** allowlist (Task 2 `PAGES`), exclude enforcement (allowlist is opt-in; Task 6 Step 3 asserts 404s), copy-engines cleanup (Task 1 Step 1), broken-link repoint (Task 1 Step 3 + build link check), em-dash strip source + guard (Task 1 Step 4, Task 2 guard), build script (Task 2), template/sidebar/CSS (Task 2 + 3), nav slot (Task 4 Step 1), workflow + trigger paths (Task 4 Step 2), gitignore output (Task 4 Step 3), URLs `/docs/*.html` (Task 2), verification local + live (Tasks 5-6). All spec sections mapped.
- **Page count:** 23 entries in `PAGES` (21 content pages named in the spec + `features/index.md` overview + `index.md` home). The spec's "~21" referred to the content set; the build count is 23 including the two index pages. Verification steps use 23.
- **Link integrity** is enforced by the build (`errors` + non-zero exit), so any missed excluded-page link fails CI rather than shipping broken.
