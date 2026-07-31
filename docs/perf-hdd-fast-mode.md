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

## Recommended order of attack

| # | Change | Integrity | Savings (HDD) | Cost |
|---|--------|-----------|---------------|------|
| 1 | 1a serialize copy/verify per rotational dest + 3 fix verify QoS | unchanged | 15–40 % | moderate |
| 2 | 2 batch `F_FULLFSYNC` at MHL checkpoints (flush-before-render invariant) | unchanged (certified ⇒ flushed) | 1–4 min / 500 files | small–moderate |
| 3 | 4 bigger HDD chunks + ring scaling | unchanged | 5–15 % | trivial |
| 4 | 5 coarser MHL checkpoint cadence | unchanged | seconds–1 min | trivial |
| 5 | 1b optional stream-verify tier (off by default, honest label) | **reduced** — no on-platter read-back | up to 45 % | small |
| 6 | 6 mkdir caching | unchanged | small-file rolls only | trivial |

**The numbers above are modeled, not measured.** Do not implement from them
directly — per-drive `F_FULLFSYNC` latency in particular varies wildly by
enclosure, and it decides whether Finding 2 is worth doing at all. Any change
here goes through the real-app smoke gate before release.

## How to measure (IOPerfProbe)

`IOPerfProbe` ([IOPerfProbe.swift](../FilmCan/Sources/Utilities/IOPerfProbe.swift))
attributes a run's wall time to per-destination I/O buckets. It is inert unless
`FILMCAN_IO_PERF=1` is set, so it ships harmlessly.

Run a Debug build from a terminal so the summary prints to stdout:

```bash
FILMCAN_IO_PERF=1 "$(ls -d ~/Library/Developer/Xcode/DerivedData/FilmCan-*/Build/Products/Debug/FilmCan.app | head -1)/Contents/MacOS/FilmCan"
```

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

**A/B protocol.** Same roll, same drive, freshly formatted, three runs each:
Finder copy, FilmCan Fast, FilmCan Fast with verification off (isolates the
verify cost from everything else). Record the bucket table for each FilmCan run.
