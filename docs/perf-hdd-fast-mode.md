# Why Fast mode is much slower than Finder on HDD destinations

Investigation report, 2026-07-31. Code read at branch `feat/card-seal` (HEAD a603dc4).
No code was changed. Findings are ranked by expected wall-time savings on a
rotational (HDD) destination. Every claim cites file:line.

## TL;DR

Finder writes each byte **once**, buffered, with kernel write-behind, and never
flushes or re-reads. FilmCan Fast mode, per byte, **writes once (uncached, queue-depth 1)
and reads once (uncached)** — and the read of file N runs *concurrently with the
write of file N+1 on the same spindle*, so the HDD head thrashes between the two
streams. On top of that it issues a **full drive-cache flush (`F_FULLFSYNC`) per
file** on every external drive, rewrites the MHL manifest every 5 files, and runs
the verify reads at a kernel-throttled I/O tier. On an SSD all of these are cheap
(no seek penalty, fast flush, concurrent mixed I/O), which is exactly why the gap
only shows on HDDs.

Worked example — 128 GB roll, 500 clips, USB 5400 rpm HDD (~110 MB/s sequential):

| Path | Time |
|---|---|
| Finder (1× buffered write) | ~19 min |
| FilmCan Fast: write 1× + verify re-read 1×, interleaved | ~29–36 min |
| + 500 × `F_FULLFSYNC` (100–500 ms each on HDD) | +1–4 min |
| + MHL checkpoints, per-file metadata, verify-tail QoS throttle | +1–2 min |
| **Total ≈ 33–42 min → 1.7–2.2× Finder** | |

None of the fixes below removes checksum verification, ASC MHL manifests, or
durability flushing. Findings 1a, 2, 3, 4, 5, 6 preserve current guarantees
outright; 1b is an explicit, gated trade-off.

> **Superseded.** The findings below were modeled from code, not measured. Two real
> A/Bs ran on 2026-07-31 and are recorded in the next two sections. Net result:
> Finding 1's cost is confirmed and quantified, Finding 3 is dead, Findings 2, 5 and
> 6 are retired as negligible, and Finding 1a is confirmed but worth ~13 %, not the
> 15-40 % modeled here. Read the measured sections before acting on any ranking below.

---

## Measured run #1 — 2026-07-31, 8 large files, USB HDD

Workload: 8 files, 12 846 MB total (~1.6 GB each), one source → one destination
(`/Volumes/TLF 4/TESTS`), Fast mode, `FILMCAN_IO_PERF=1`. Chunk size 3.99 MB
average over 3 218 chunks, which confirms the 4 MB HDD class at
[Constants.swift:46](../FilmCan/Sources/Models/Constants.swift#L46).

| Bucket | Time | n | Throughput |
|---|---|---|---|
| source read | 142.95 s | 3218 | 89.9 MB/s |
| dest write | 131.97 s | 3218 | 97.3 MB/s |
| verify re-read | 101.06 s | 3218 | 127.1 MB/s |
| dest hash | 1.81 s | 3218 | 7 099 MB/s |
| verify hash | 1.38 s | 3218 | 9 337 MB/s |
| source hash | 1.12 s | 3218 | 11 432 MB/s |
| cache flush | 1.31 s | 8 | 163.1 ms/call (max 288.9) |
| rename | 0.05 s | 8 | 6.3 ms/call |
| temp create | 0.05 s | 16 | 3.4 ms/call |
| mhl render | 0.04 s | 2 | 21.9 ms/call |

Wall 247.9 s. Bucket sum 381.7 s, so the overlap factor is 1.54×.
`settle sleep` is absent because it is paranoid-only
([FanOutCopier.swift:1672-1681](../FilmCan/Sources/Services/FanOutCopier.swift#L1672-L1681)).

### The gap is the verify pass, and nothing else

```
source read 142.95 s  +  verify re-read 101.06 s  =  244.01 s   (98.4 % of wall)
```

Finder moved the same set in 146 s = **88.0 MB/s**. FilmCan's copy phase ran at
**89.9 MB/s**. The copy phase is **at parity with Finder**. The measured gap is
247.9 − 146 = **101.9 s**, and the verify re-read is **101.06 s**. That accounts
for 99.2 % of the difference. Overall ratio: **1.70× Finder**.

### What this refutes

- **Finding 1's mechanism is wrong.** The report claimed head thrash between the
  verify read of file N and the write of file N+1 degrades the copy. It does not:
  the copy runs at Finder speed. The verify is simply an extra full read pass that
  Finder never performs. The cost is real, the explanation was not.
- **Finding 1a (serialize copy and verify per rotational dest) is dead.** Measured
  time is already additive (244.0 s of stream work in 247.9 s of wall), so the
  existing overlap at [FanOutCopier.swift:1009-1014](../FilmCan/Sources/Services/FanOutCopier.swift#L1009-L1014)
  is already yielding ~0 on one spindle. Serializing it deliberately would also
  yield ~0. It would only remove the 519 ms `verify re-read` outlier (16× the
  31.4 ms mean), which is a jitter fix, not a throughput fix.
- **Finding 3 (`.utility` QoS throttling) is dead.** The verify re-read is the
  *fastest* stream in the run at 127.1 MB/s, well above the 89.9 MB/s copy. It is
  not being throttled.
- **Hashing is not a target, ever.** All three hash buckets total 4.31 s = 1.7 %
  of wall. xxh128 runs at 7–11 GB/s, three orders of magnitude above the disks.

### What this reveals that the report missed

- **The copy phase is source-bound, not destination-bound.** Source reads at
  89.9 MB/s; the destination accepts 97.3 MB/s. The report assumed the destination
  HDD was the constraint. Any destination-side write optimization is capped at
  roughly 8 % during the copy phase.
- **A read-back verify has a hard floor.** 12 846 MB ÷ 127.1 MB/s = 101 s. On one
  spindle you cannot make an on-platter read-back cheaper than the time to read the
  platter. The destination head is already ~92 % busy during the copy
  (131.97 s of blocking writes inside a 142.95 s phase), so there is no idle
  capacity to hide the verify in.

**Therefore: on large-file workloads the only lever that closes the Finder gap is
not reading the destination back** — Finding 1b, the explicit gated trade-off.
Micro-optimizing anything else cannot recover more than ~2 % of wall time.

### What this run could not test

The workload was 8 files, so every per-file cost is invisible. Findings 2, 5 and 6
live there. See run #2 below, which settles them.

---

## Measured run #2 — 2026-07-31, 5 mixed-size clips, same USB HDD

Workload: 5 clips of deliberately mixed sizes, 24 977 MB total, same source and same
destination as run #1, Fast mode. 6 247 chunks at 4.00 MB average.

| Bucket | Time | n | Throughput | vs run #1 |
|---|---|---|---|---|
| dest write | 439.01 s | 6247 | 56.9 MB/s | **−41 %** |
| verify re-read | 374.18 s | 6247 | 66.7 MB/s | **−48 %** |
| source read | 285.45 s | 6247 | 87.5 MB/s | −2.7 % |
| dest hash | 8.50 s | 6247 | 2 938 MB/s | |
| source hash | 6.65 s | 6247 | 3 755 MB/s | |
| verify hash | 4.88 s | 6247 | 5 113 MB/s | |
| cache flush | 0.90 s | 5 | 180.0 ms/call | |
| rename | 0.28 s | 5 | 55.1 ms/call | |
| temp create | 0.18 s | 10 | 17.9 ms/call | |
| mhl render | 0.04 s | 2 | 20.4 ms/call | |

Wall 555.1 s. Finder 285 s. Ratio **1.95×**.

### The governing model (fits both runs exactly)

FilmCan pushes **twice** the bytes through the destination that Finder does: it writes
each byte once, then reads it back to verify. Finder writes once and never reads.
So the destination head, not the source, sets the wall time:

```
wall  =  2 × bytes  ÷  destination aggregate throughput
```

| | bytes | dest aggregate | predicted | measured |
|---|---|---|---|---|
| run #1 | 2 × 12 846 MB | 103.6 MB/s | 248 s | 247.9 s |
| run #2 | 2 × 24 977 MB | 90.0 MB/s | 555 s | 555.1 s |

Finder is **source**-bound in both runs, at 88.0 and 87.6 MB/s — and FilmCan's own
`source read` bucket independently measures that same source at 89.9 and 87.5 MB/s.
The ratio therefore falls out as `2 × source_speed ÷ dest_aggregate`:
2 × 88.0 ÷ 103.6 = **1.70** (run #1), 2 × 87.6 ÷ 90.0 = **1.95** (run #2). Both match.

The user's own summary — "copy time ×2 for checksum" — is literally correct. It is
2× the destination I/O.

### Interleaving costs ~13 %, so Finding 1a is back

Run #2's destination lanes overlap: `dest write 439.01 + verify re-read 374.18 =
813.19 s` of destination work inside a **555.1 s** wall. Exceeding the wall is
arithmetic proof that the head served both streams at once. The copy group and the
verify lane run concurrently by construction — `drainVerifies` is launched with
`async let` behind a 64-deep channel
([FanOutCopier.swift:1017-1022](../FilmCan/Sources/Services/FanOutCopier.swift#L1017-L1022)),
so the copy side can run up to 64 files ahead and never waits for the verifier.

The contention is destination-only: both destination lanes lost ~45 % of their run #1
throughput while `source read` lost 2.7 %. The source is a different device and was
never contended. Per-call maxima confirm it — `dest write` max went 222.65 → 811.74 ms
and `verify re-read` max 519.10 → 802.11 ms.

Serializing the verify behind the copy on a rotational destination predicts:
copy phase 24 977 ÷ 87.5 = 285.5 s (source-bound, i.e. Finder speed) + verify
24 977 ÷ 127.1 = 196.5 s at run #1's uncontended read speed = **482 s**, saving 73 s
(**13 %**) and moving the ratio 1.95 → 1.69.

**This retracts the run #1 verdict that Finding 1a was dead.** Run #1's totals
(233.03 s of destination work in a 247.9 s wall) were *consistent* with serial
execution but did not prove it; run #2's exceed the wall and do prove concurrency.
Uniform 1.6 GB files kept the pipeline in near-lockstep; mixed clip sizes let one long
verify straddle several copies. Real cards have mixed clip sizes, so **run #2 is the
representative case**.

Finding 3 stays dead: even under contention the verify re-read (66.7 MB/s) is faster
than the concurrent write (56.9 MB/s). It is not being QoS-throttled.

### Findings 2, 5 and 6 are retired

Per-file costs totalled **1.40 s = 0.25 % of wall**. The run #1 extrapolation assumed a
500-clip card, which is not the real shape of the workload: a camera card is typically
**under 100 clips**, a few MB to a few tens of GB each. At 100 files the whole per-file
group is ~30 s worst case on a ~9-minute run — 3-5 %, behind everything else. Neither
`F_FULLFSYNC` batching (Finding 2), MHL checkpoint cadence (Finding 5), nor mkdir
caching (Finding 6) is worth doing for throughput. Finding 2 may still be worth it for
the *jitter* it causes, not the total.

### Two side observations, not perf findings

- `MainThreadWatchdog` logged repeated 103-228 ms janks with `region='idle'` throughout
  run #2. The main thread stalls during copy. Separate UI issue.
- Hash per-call maxima are implausible for xxh128 on 4 MB (99.73, 125.46, 160.89 ms
  against sub-millisecond means). That is thread starvation, not hashing cost. Hash
  totals remain 3.6 % of wall.

---

## Finding 1 — Fast mode re-reads every destination byte, interleaved with the next file's writes

**Where.** The verify lane re-reads the written file from disk in *both* Fast and
Paranoid modes — [FanOutCopier.swift:1712–1726](../FilmCan/Sources/Services/FanOutCopier.swift)
("Re-read every destination from disk (fast AND paranoid)"), via
`rereadHashDetached` with `F_NOCACHE`
([FanOutCopier.swift:1964](../FilmCan/Sources/Services/FanOutCopier.swift)).
This was a deliberate audit hardening (commit `ceed823` "fast mode re-reads
destination from disk (C-1)") — before it, Fast trusted the writer's streamed hash.

**Why it hurts on HDD.** The pipeline design ("file N verifies while file N+1
copies", [FanOutCopier.swift:1009–1014](../FilmCan/Sources/Services/FanOutCopier.swift))
means the destination drive serves a **write stream and a read stream at the same
time**. Because both the write handle and the re-read handle use `F_NOCACHE`
([DestWriter.swift:94](../FilmCan/Sources/Services/DestWriter.swift),
[FanOutCopier.swift:1964](../FilmCan/Sources/Services/FanOutCopier.swift)), the
re-read can never be served from RAM — every verify byte comes off the platter.
On one spindle that is a seek between the write frontier and the read position on
every scheduler slice; effective throughput for both streams drops to roughly
50–80 % of sequential. Total device I/O is 2× the payload, at a degraded rate.

**Why SSD hides it.** Flash has no seek penalty; mixed read/write at these queue
depths runs near full speed, and read bandwidth usually exceeds write bandwidth,
so the re-read hides almost entirely behind the ongoing writes.

**Options.**

- **1a. HDD-aware verify scheduling (no integrity change).** When
  `DriveSpeedClassifier` says a destination is rotational
  ([DriveSpeedClassifier.swift:68–75](../FilmCan/Sources/Services/DriveSpeedClassifier.swift)),
  stop overlapping copy and verify **on that drive**: either verify each file
  before starting the next file's write (2 long seeks per file — negligible for
  clip-sized files), or batch all verifies after the copy phase. Same bytes
  verified, same hashes, same MHL — only the schedule changes. Keep the overlap
  for SSD destinations, where it is a pure win.
  **Savings:** removes the thrash delta, ~15–40 % of total wall time.
  **Cost:** moderate — a per-dest gate in the copy/verify pipeline
  ([FanOutCopier.swift:1013–1101](../FilmCan/Sources/Services/FanOutCopier.swift)),
  ~1–2 days incl. QA on a real HDD.

- **1b. Gated "stream-verify" Fast tier (explicit trade-off).** Add a setting
  (off by default, clearly labeled) that lets Fast mode accept the writer-side
  streamed xxh128 ([FanOutCopier.swift:1344–1346, 1416](../FilmCan/Sources/Services/FanOutCopier.swift))
  as the destination hash and skip the disk re-read. This halves destination I/O.
  **Integrity trade-off:** the streamed hash proves the bytes that *reached the
  write call* match the source; it does **not** prove the bytes on the platter are
  readable/intact — the exact gap audit C-1 closed. It still catches source-read
  and channel corruption. If offered, name it honestly (e.g. "Verify in transit
  only") and keep the current behavior as the default.
  **Savings:** up to ~45 % on HDD. **Cost:** small (setting + one branch in
  `verifySource`), but policy/documentation work matters more than the code.

## Finding 2 — `F_FULLFSYNC` per file, on every external drive

**Where.** `requiresFullFsync` is true for *any* non-internal volume — not just
exFAT/NTFS — [DriveSpeedClassifier.swift:51–57](../FilmCan/Sources/Services/DriveSpeedClassifier.swift)
(`if !info.isInternal { return true }`). `DestWriter.finalize` then issues
`fcntl(F_FULLFSYNC)` on **every file** before its rename
([DestWriter.swift:138–149](../FilmCan/Sources/Services/DestWriter.swift));
internal dests get a per-file `synchronize()` (plain fsync,
[DestWriter.swift:151](../FilmCan/Sources/Services/DestWriter.swift)).

**Why it hurts on HDD.** `F_FULLFSYNC` forces the drive to empty its entire write
cache; on spinning USB drives that is commonly 100–500 ms per call. 500 clips →
1–4 minutes of pure flushing. Finder never does this. On SSDs the flush is
typically 5–30 ms, so the cost stays invisible there.

**Fix (integrity-preserving).** Move the durability point from *per file* to *per
MHL checkpoint*: plain `fsync` per file (bytes handed to the device), then one
`F_FULLFSYNC` **immediately before** each manifest render (every
`mhlFlushEveryFiles` files, [Constants.swift:18](../FilmCan/Sources/Models/Constants.swift))
and before `seal()`. Ordering is the invariant: **no MHL entry may be rendered to
disk before the bytes it certifies are flushed**. A power cut then loses at most
the files since the last checkpoint — which are *absent from the manifest*, so
resume re-copies them ([FanOutCopier.swift:780–798](../FilmCan/Sources/Services/FanOutCopier.swift)
treats unrecorded/missing/size-mismatched files as needing copy). Nothing ever
gets certified without a full flush, which is the guarantee that matters.
**Savings:** ~1–4 min per 500 files on HDD; also removes a tail cost on external
SSDs with slow flush firmware. **Cost:** small–moderate — batching state in
`DestWriter`/verify lane + the ordering hook; needs a careful crash-window
comment and a QA pass. Could be gated ("Flush every file" vs "Flush at
checkpoints") if you want the old behavior selectable.

## Finding 3 — Verify reads run at `.utility` QoS (kernel I/O-throttled)

**Where.** `rereadHashDetached` runs in `Task.detached(priority: .utility)`
([FanOutCopier.swift:1960](../FilmCan/Sources/Services/FanOutCopier.swift)).

**Why it hurts.** macOS maps utility QoS to a throttled I/O tier: when
default-tier I/O (the copy writes) is active on the system, utility-tier reads
are delayed with back-off. During the run this *adds* to Finding 1's contention
pattern; worse, it silently converts the intended overlap into "verify limps
behind and finishes in a long tail" — and the job cannot end until the verify
lane drains ([FanOutCopier.swift:1099–1100](../FilmCan/Sources/Services/FanOutCopier.swift)).
On SSD the device is fast enough that the throttle window barely registers.

**Fix.** Issue verify I/O at the same QoS as the copy (or set an explicit
`IOPOL_DEFAULT` on the re-read thread). If Finding 1a lands (serialized verify on
HDD), this is what makes the verify phase run at full device speed. No integrity
impact. **Cost:** trivial. **Savings:** hard to bound alone; bundled with 1a it
is what delivers the "clean sequential read" speed.

## Finding 4 — 4 MB chunks + queue-depth-1 uncached I/O for the slowest class

**Where.** The HDD/exFAT/unknown classes get the *smallest* chunk (4 MB vs 8/16 MB
for SSD/NVMe) — [Constants.swift:41–50](../FilmCan/Sources/Models/Constants.swift).
Writes are synchronous per chunk on an `F_NOCACHE` handle
([DestWriter.swift:94, 103](../FilmCan/Sources/Services/DestWriter.swift));
the verify read loop is read-4MB → hash → read-next with no readahead (uncached
handle, [FanOutCopier.swift:1964–1985](../FilmCan/Sources/Services/FanOutCopier.swift)),
so the disk idles during every hash gap.

**Why it hurts on HDD.** With caching off there is no kernel clustering or
readahead to amortize per-command latency; each 4 MB transfer is a full round
trip (USB bridge command overhead included), and the device sees QD1. Cost is a
steady 5–15 % tax on both streams. On NVMe/USB-SSD, per-command latency is tens
of microseconds — invisible.

**Fix.** Raise the HDD-class chunk to 16–32 MB and scale
`ringCapBytesPerDest` ([Constants.swift:21–33](../FilmCan/Sources/Models/Constants.swift))
so `channelCapacity = ringCap / chunk` stays ≥ 2–4
([FanOutCopier.swift:652–653](../FilmCan/Sources/Services/FanOutCopier.swift));
optionally double-buffer the verify read (issue read N+1 while hashing N).
Memory stays bounded (ring cap is the ceiling). No integrity impact.
**Cost:** trivial for the constants; small for double-buffering.
**Savings:** ~5–15 % on HDD.

## Finding 5 — MHL manifest rewritten in full every 5 files

**Where.** `mhlFlushEveryFiles = 5` ([Constants.swift:18](../FilmCan/Sources/Models/Constants.swift));
each checkpoint re-renders the *entire growing* XML and writes it atomically
(temp + rename) onto the busy destination —
[ASCMHLWriter.swift:47, 82–111](../FilmCan/Sources/Services/ASCMHLWriter.swift)
(same for [SimpleMHLWriter.swift:35](../FilmCan/Sources/Services/SimpleMHLWriter.swift)).
For N files that is N/5 rewrites of an O(N)-sized file: O(N²) bytes plus two
metadata ops per checkpoint, each stealing seeks from the copy stream.
Note: `mhlFlushEveryBytes` ([Constants.swift:19](../FilmCan/Sources/Models/Constants.swift))
and `writeFlushEveryBytes` ([Constants.swift:39](../FilmCan/Sources/Models/Constants.swift))
are **defined but referenced nowhere** — the byte-based cadence and the
"cached writes + periodic fsync" design they describe were never wired up.

**Fix.** Coarsen the cadence (e.g. every 25 files *or* every `mhlFlushEveryBytes`,
whichever first), or append to a tiny journal sidecar and render the full XML only
at seal. The code already documents that a crash costs only re-copying
uncertified files ([FanOutCopier.swift:1179–1186](../FilmCan/Sources/Services/FanOutCopier.swift)),
so a coarser checkpoint changes nothing about correctness — and it pairs
naturally with Finding 2's flush-per-checkpoint. **Cost:** trivial.
**Savings:** seconds on clip rolls; up to ~1 min on thousand-file rolls.

## Finding 6 — Fixed per-file, per-destination overhead (small-file rolls)

**Where.** Per file per destination: `createDirectory` attempted even when the
parent exists ([FanOutCopier.swift:1271–1272](../FilmCan/Sources/Services/FanOutCopier.swift)),
temp-file create + registered/unregistered with the OrphanCleaner actor
([DestWriter.swift:79–83](../FilmCan/Sources/Services/DestWriter.swift)),
`rename(2)` ([DestWriter.swift:158–163](../FilmCan/Sources/Services/DestWriter.swift)),
a fresh `DestWriter` actor per file, and the finding-2 fsync. Each metadata op on
a journaled HDD costs a seek; budget ~10–30 ms of fixed cost per small file.

**Fix.** Cache "directory already created" per roll; skip the redundant mkdir.
The rest is dominated by Finding 2. Only matters for stills/audio rolls with
thousands of small files. **Cost:** trivial. **Savings:** small, workload-specific.

## Finding 7 — Mixed-speed fan-out runs at the slowest destination's pace (known, by design)

The source reader broadcasts each chunk to every destination's bounded ring and
blocks when the slowest ring is full
([FanOutCopier.swift:1541–1548](../FilmCan/Sources/Services/FanOutCopier.swift);
ring = 32–96 MB, [Constants.swift:21–33](../FilmCan/Sources/Models/Constants.swift)).
Copying SSD + HDD together therefore degrades the SSD to HDD pace. That is the
price of reading the source exactly once; decoupling would need a second source
read for the slow dest (an explicit user choice, e.g. "copy slow drive in a
second pass"), or unbounded buffering (rejected for memory reasons —
[DestWriter.swift:88–94](../FilmCan/Sources/Services/DestWriter.swift)). Worth a
sentence in the docs; not a code change recommendation.

## Side note — Paranoid mode's extra HDD costs (out of scope, but adjacent)

- 1 s settle sleep **per file** whenever any destination requires full fsync
  ([FanOutCopier.swift:1654–1661](../FilmCan/Sources/Services/FanOutCopier.swift)) —
  500 files ≈ 8 min of pure sleep. Could be gated to exFAT/known-liar drives
  only, rather than all externals.
- Paranoid additionally re-reads the **source** per file
  ([FanOutCopier.swift:1694](../FilmCan/Sources/Services/FanOutCopier.swift)), so
  device I/O is 3× payload.

## What is already right (checked, not the problem)

- Spotlight indexing is disabled on source + dest volumes for the run
  ([TransferViewModel.swift:162–168](../FilmCan/Sources/ViewModels/TransferViewModel.swift)).
- Hashing is xxh3-128 via dlopen'd libxxhash, zero-copy per chunk
  ([XXHash.swift:128–132](../FilmCan/Sources/Utilities/XXHash.swift)) — CPU is
  not a factor at HDD speeds.
- Progress emits are throttled (10/s copy, per-16 MB verify —
  [FanOutCopier.swift:1299–1302, 1957](../FilmCan/Sources/Services/FanOutCopier.swift))
  and chunks are shared by reference across destinations (no per-dest copies).
- The autorelease pool is drained per chunk in the re-read loop
  ([FanOutCopier.swift:1968–1984](../FilmCan/Sources/Services/FanOutCopier.swift)).
- `F_NOCACHE` itself is load-bearing: without it a multi-hundred-GB job filled the
  unified buffer cache and crashed the machine
  ([DestWriter.swift:88–94](../FilmCan/Sources/Services/DestWriter.swift),
  [FanOutCopier.swift:1511–1517](../FilmCan/Sources/Services/FanOutCopier.swift)).
  Don't remove it — Findings 1a/3/4 work *with* it.

## How the industry solves this (researched 2026-07-31)

Short version: **nobody avoids the 2× destination I/O. They schedule it differently.**

### OffShoot (ex-Hedge) — three modes, renamed in 24.3

| Mode (pre-24.3 name) | Source | Destination | Cost |
|---|---|---|---|
| **Transfer** (Checkpoint OFF) | read once + checksum | **file size only** | 1× |
| **Source** (Checkpoint ON, Backup) | *"contents are independently read twice"* | **file size only** | 2× source, 1× dest |
| **Source & Destination** (Checkpoint ON, Archive) | checksum | **full read-back**, three checksums total | *"twice as long as Transfer Verification"* |

Two scheduling features FilmCan lacks:

- **Background destination reads.** The 2019 Newsshooter benchmark notes Hedge
  *"completes its initial verification while continuing background destination reads"*,
  and warns the completion tick therefore *"means something different than ticks from
  other software."* The job reports done; the destination read-back keeps running.
- **Standalone Verification** (24.3): double-click an MHL file and OffShoot re-locates
  every referenced file and checksums it against the stored values — verification fully
  decoupled from the copy, run whenever.

OffShoot explicitly warns that Transfer mode *"should not be used if you plan to delete
source files."* That is the honest framing of the trade-off.

### Silverstack (Pomfort)

Source verification is **overlapped** with destination verification, so per Pomfort it
*"usually comes at no performance cost… the duration of the copy process is not
extended by copying with source verification."* Scheduling is user-selectable:
**Included in Copy Job** (default), **Separate (per Job)** — verification can be
suspended and resumed later, e.g. after transcoding — and **Cascading Copy**, which
allows *different security levels per destination*.

### ShotPut Pro

Nine checksum algorithms (XXHash-64/3-64/128, MD5, SHA-1/256/512, C4, CRC-32, file-size
comparison), but conventional in-line verification with no deferral mechanism. It was
the **slowest** tool in the Newsshooter test.

### Benchmark, 212 GB to 3 destinations (Newsshooter, 2019 — no Finder baseline)

| Tool | Time | vs Hedge |
|---|---|---|
| Hedge | 22:16 | 1.00× |
| YoYotta | 25:46 | 1.16× |
| Silverstack | 26:11 | 1.18× |
| ShotPut Pro | 30:31 | 1.37× |

Hedge's own marketing claims Fast Lane is *"at least a factor of 2.5"* over traditional
checksum transfer, reaching *"as fast as a standard non-verified Finder copy/paste."*
That implies the traditional in-line tier costs ~2.5× Finder. **FilmCan measures
1.70-1.95×, so FilmCan's thorough tier is already at or better than the industry's
thorough tier.** The gap the user perceives is not slowness — it is that FilmCan ships
only the thorough tier and puts all of it on the critical path.

### Head-to-head on the run #2 workload (measured 2026-07-31)

| Tool | Wall | vs Finder |
|---|---|---|
| Finder (no verification) | 285 s | 1.00× |
| **FilmCan, Fast** | **555.1 s** | **1.95×** |
| Hedge 21.3.2 | 565 s | 1.98× |

**FilmCan is 2 % faster than Hedge on identical work.** Hedge reported the job finished
with an estimated 20-30 % of verification still outstanding, then kept reading in the
background — which is the background-verification model working exactly as documented.
Its *displayed* time is shorter; its *actual* time is slightly longer than FilmCan's.

This closes the original question. FilmCan was never the slow one. It reports honestly
and the competition reports early.

**Product decision, 2026-07-31: background verification is rejected.** The user prefers
the completion signal to mean the work is actually done. Items 1 and 4 below are
therefore parked, and item 3 (serialising the verify lane on rotational destinations,
−13 %, integrity untouched) becomes the top remaining lever.

### What this changes about the recommendation

1. **The cheap tier competitors actually ship is "destination file size only"** — not a
   hash of the write buffer. That distinction matters: file-size checking is weak but
   *honest and non-zero*. Re-hashing the in-memory buffer, which is what FilmCan did
   before `ceed823`, is not a weaker check — it is **no check at all**, since both
   hashes come from the same bytes and can never disagree. Do not resurrect it.
2. **Nobody ships sampled/percentage read-back.** The idea floated earlier in this
   investigation has no industry precedent; the simpler size-only tier occupies that
   slot.
3. **The winning move is scheduling, and FilmCan already owns the prerequisite.** It
   writes ASC MHL chains, which is exactly the asset OffShoot's Standalone Verification
   consumes. Deferred and background verification are scheduling features on top of
   existing manifests, not new cryptography, and they cost **nothing** in integrity.
4. **Paranoid mode has a separate, free win.** Silverstack overlaps the source re-read
   with destination verification and charges nothing for it. FilmCan serializes it
   behind a 1 s settle sleep ([FanOutCopier.swift:1668-1681](../FilmCan/Sources/Services/FanOutCopier.swift#L1668-L1681)).

Sources: [OffShoot verification docs](https://docs.hedge.video/offshoot/features/verification),
[OffShoot 24.3 release notes](https://hedge.co/blog/offshoot-24-3),
[Newsshooter offload benchmark](https://www.newsshooter.com/2019/10/28/what-is-the-fastest-offload-software/),
[CineD on Hedge Fast Lane](https://www.cined.com/hedge-for-mac-1-3-checksum-file-transfer/),
[Pomfort verification behaviors](https://pomfort.com/article/backup-shooting-data-verification-behavior/),
[Pomfort on source verification](https://pomfort.com/article/how-source-verification-helps-identify-underlying-problems-in-your-copy-process/),
[ShotPut Pro verification options](https://imagineproducts.freshdesk.com/support/solutions/articles/35000203787-what-are-the-differences-between-the-verification-options-available-on-shotput-pro-).

## Recommended order of attack

Revised after runs #1 and #2. Savings are quoted against run #2 (555.1 s wall,
1.95× Finder), the representative mixed-clip-size case.

| # | Change | Integrity | Time to card-pull | Precedent |
|---|--------|-----------|-------------------|-----------|
| 1 | **Background destination verification** — copy completes, read-back continues behind, status goes copied → verified | **unchanged** | **−49 %, ~1.00×** | OffShoot's background destination reads |
| 2 | **Standalone verify from an existing ASC MHL chain** — verify a drive later, at the office | **unchanged** | n/a (moves it off set entirely) | OffShoot 24.3 Standalone Verification; Silverstack "Separate (per Job)" |
| 3 | 1a bound how far the copy lane runs ahead of the verify lane | unchanged | **−13 % modeled, not measured** | knob shipped, see below |
| 4 | Per-destination verification level (full on archive, size-only on shuttle) | reduced, per-dest, explicit | varies | Silverstack Cascading Copy |
| 5 | Overlap Paranoid's source re-read instead of serializing it behind the settle sleep | unchanged | Paranoid only | Silverstack, which charges nothing for source verification |
| 6 | 4 bigger HDD chunks | unchanged | unmeasured, plausibly part of item 3's 13 % | — |
| — | ~~2 batch `F_FULLFSYNC`~~ / ~~5 MHL cadence~~ / ~~6 mkdir caching~~ | — | **0.25 % measured** | **retired** — cards are <100 clips, so per-file cost never dominates |
| — | ~~3 fix verify QoS~~ | — | **0 %** | **dead** — verify re-reads faster than the concurrent write |
| — | ~~1b trust the streamed dest hash~~ | **none** | — | **forbidden** — identical to the `ceed823` C-1 bug; both hashes come from the same buffer and can never disagree |

**Items 1 and 2 are the answer.** They cost nothing in integrity, they are what the
market leader actually does, and FilmCan already writes the ASC MHL chains they depend
on. The earlier framing of this document — that closing the gap requires trading away
verification — was wrong. The total I/O does not shrink; it comes off the critical path.

The one real design constraint: if the destination read-back is deferred, the UI must
not let the user eject, wipe or reformat the card until verification has actually
finished. OffShoot states the same rule for its Transfer mode — *"should not be used if
you plan to delete source files."*

Any change here goes through the real-app smoke gate before release.

## How to measure (IOPerfProbe)

`IOPerfProbe` ([IOPerfProbe.swift](../FilmCan/Sources/Utilities/IOPerfProbe.swift))
attributes a run's wall time to per-destination I/O buckets. It is inert unless
`FILMCAN_IO_PERF=1` is set, so it ships harmlessly.

Run a Debug build from a terminal so the summary prints to stdout:

```bash
FILMCAN_IO_PERF=1 "$(ls -dt ~/Library/Developer/Xcode/DerivedData/FilmCan-*/Build/Products/Debug/FilmCan.app/Contents/MacOS/FilmCan 2>/dev/null | head -1)"
```

The glob targets the **binary**, not the `.app`, and sorts newest-first with `-t`.
Both matter: several `DerivedData/FilmCan-*` directories usually exist, an
interrupted build leaves an `.app` bundle with no executable inside it, and that
empty bundle often has the newest directory mtime. Globbing the `.app` alphabetically
(or even by mtime) picks it and fails with `no such file or directory`.

For a release/staged build, read it from the unified log instead:

```bash
log stream --predicate 'category == "FilmCan"' --info
```

The summary is emitted once per `FanOutCopier.run()`, via a `defer`, so it prints
on cancel and on error too. Each row is one bucket at one destination:

```
=== FilmCan I/O perf — wall 1840.2s ===
[LaCie-HDD]
  dest write      612.40s  n=31200  mean=  19.628ms  max=   210.44ms     214.1 MB/s
  cache flush     186.02s  n=500    mean= 372.040ms  max=  1180.30ms
  verify re-read  735.10s  n=31200  mean=  23.561ms  max=   295.10ms     178.3 MB/s
```

**Reading it.** `cache flush` mean is the number that decides Finding 2 — anything
over ~50 ms per call means batching wins big; the `max` column tells you whether
the drive is a bimodal flusher (a mean of 40 ms with a max of 900 ms still hurts).
Comparing `dest write` MB/s against `verify re-read` MB/s **during the same run**
quantifies Finding 1's thrash: if both sit far below the drive's sequential
figure, the two streams are fighting for the head. `sum(buckets) ≪ wall` means
time is going somewhere not yet instrumented — say so rather than guessing.

**Sleep invalidates a measurement.** Until 2026-08-01 the app held no power assertion,
so an unattended run could be suspended and its drives spun down mid-copy — one run
went from a 3-minute ETA to 40+ minutes across a sleep/wake. `PowerAssertion` now holds
`idleSystemSleepDisabled` plus an IOKit `PreventDiskIdle` for the whole run. Verify it
is live during a backup with `pmset -g assertions`. Discard any timing collected from a
build without it.

**A/B protocol.** Same roll, same drive, freshly formatted, three runs each:
Finder copy, FilmCan Fast, FilmCan Fast with verification off (isolates the
verify cost from everything else). Record the bucket table for each FilmCan run.

## Pending experiment — verify run-ahead depth

`BoundedChannel.send` blocks only once `buffer.count >= capacity`, and `receive()`
dequeues when the verifier *starts* a file, not when it finishes. At the historical
capacity of 64 the copy lane therefore never waits, which is why run #2 overlapped so
heavily. `Constants.verifyRunAheadFiles()` now exposes that depth, overridable with
`FILMCAN_VERIFY_RUNAHEAD`. **The default is unchanged at 64**, so shipped behaviour is
identical until the experiment settles the question.

The question is genuinely open, because two regimes predict opposite results:

- **Phase separation** (copy everything, then verify everything) is what the −13 %
  estimate models. It assumes each lane regains its uncontended throughput.
- **Per-file alternation** (write file N, immediately read file N back) may beat it
  outright: the head is already parked on the bytes just written, so the read is a short
  seek rather than a long one. The −13 % model does not account for this at all.

Lowering the capacity moves toward alternation, not toward phase separation. Run:

```bash
FILMCAN_VERIFY_RUNAHEAD=1 FILMCAN_IO_PERF=1 "$(ls -dt ~/Library/Developer/Xcode/DerivedData/FilmCan-*/Build/Products/Debug/FilmCan.app/Contents/MacOS/FilmCan 2>/dev/null | head -1)"
```

Run #2 (555.1 s, 24 977 MB, 5 mixed clips) is already the capacity-64 baseline for that
workload, so only depths 1 and 4 still need measuring. The number to watch is
`dest write` + `verify re-read` against the wall: at 64 it was 813.19 s inside 555.1 s
(overlap factor 1.47). If bounding the depth helps, that sum should fall toward the wall
and both lanes should recover throughput. **If it does not, this lever is dead and the
1.70× floor stands** — say so and stop, rather than building the heavier explicit gate.
