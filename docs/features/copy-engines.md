# Copy Engine

FilmCan copies with one purpose-built engine: the **FilmCan Engine**, a fan-out
copier designed for cinema rushes: read the source once, write to every
destination at once, verify with cinema-grade hash lists, and recover a failed
drive with one click.

---

## How it works

1. **Read source once.** A single read pass pulls each file straight off the
   card, bypassing the Mac's memory cache, so a huge offload doesn't fill up
   your RAM with cached data.
2. **Broadcast to every destination at once.** One bounded channel feeds a
   writer task per drive. The slowest drive sets the pace; faster drives idle
   briefly. Destination writes bypass the memory cache too, so a
   multi-hundred-GB copy stays memory-bounded.
3. **Honest writes.** On exFAT, external, and USB drives, FilmCan forces the
   drive's own cache to flush to the physical media before marking a file
   done, so "copy finished" means the bytes are actually on the drive, not
   just queued in a buffer. Internal drives use the Mac's normal, faster save
   method, since they don't have this problem.
4. **Atomic finalize.** Each file is written to a hidden temp file first, then
   swapped into its final name only once it's complete, so you never see a
   half-written file at the destination.
5. **Verify** (see modes below), overlapping the copy of the next file.
6. **MHL per source root.** One sealed ASC-format `.mhl` per source root,
   aggregating every file in that tree, at `<dest>/.filmcan/hashlists/<root>.mhl`.

### Verify pipeline

Verification runs on its own lane **while the next file is still copying**, so a
paranoid re-read no longer roughly doubles the wall time. It mostly hides behind
the copy. Only the last file's verify tail runs alone (shown as "Verifying…").

---

## Verification modes

Pick in **Backup Editor → Options → Verification**.

| Mode | Catches | Cost |
|---|---|---|
| **Off** | nothing | fastest, no hashing or checking |
| **Fast** *(default for new projects)* | RAM bit-flips, PCI/USB corruption, partial writes, via the hash computed during the copy | none beyond the copy; no re-read |
| **Paranoid** | all of Fast **+** drive-firmware silent corruption, OS-cache lies, bit rot at rest, re-reads every destination (and the source) from disk and re-hashes | extra disk I/O, mostly overlapped with copying |

---

## Resume: re-running skips what's already there

Re-running a backup (including after **Stop**) does **not** recopy files that are
already done. A file is skipped when it is recorded in **every** destination's
hash list **and** still present on disk there. Only the remaining files are
copied; the progress row reads *"Resuming: N already backed up, copying the
rest."*

- If the whole backup is already present, no history card is added. An **Already
  backed up** popup appears instead, with a **Verify data** button (the same
  hash-list check as History's *Check data*).
- A file deleted from a destination is re-copied (presence is checked, not just
  the hash list).
- **Force re-copy** (Options) disables resume skip and re-copies everything.
- Caveat: with a `{date}` folder template, resuming on a *different day* re-copies
  into that day's folder (earlier files aren't matched).

---

## Directory sources

Drop a mounted card (e.g. `/Volumes/A001_C002`) or any folder. FilmCan walks the
tree, mirrors the layout under each destination, and aggregates one MHL per
source root. Hidden macOS junk (`.Spotlight-V100`, `.fseventsd`, `.DS_Store`,
`.Trashes`) is skipped automatically.

---

## Failed drives, one-click repair

When a drive fails mid-copy or fails verify, a **Retry** button appears on its
row, opening the repair sheet:

- **From source**, re-runs the engine for that single drive, pulling from the
  original source(s) if still mounted.
- **From sibling**, reads files from a verified neighbor drive's MHL, copies
  them to the failed drive, and hash-verifies each. The source card no longer
  needs to be mounted. Cinema-set workflow: keep going, fix the drive at lunch.

**From sibling** enables only when at least one other destination from the same
job succeeded.

---

## Performance & memory

- **Memory-bounded.** Source reads and destination writes bypass the Mac's
  memory cache, and the paranoid re-read releases memory as it goes chunk by
  chunk. In-flight memory is just a small per-destination buffer, capped
  between 32 MB and 96 MB depending on how much RAM the Mac has.
- **Multi-source concurrency** is capped to the number of distinct source
  physical drives, three clips from one card copy sequentially (no
  head-thrashing); card-A and card-B copy in parallel.
- **Chunk size** is chosen from the slowest destination's bus, 4 MB on slow
  buses, up to 16 MB on Thunderbolt / internal.
- **Live speed & ETA** use a moving average of recent combined (copy + verify)
  throughput, so the estimate is stable and honest from the first few seconds.

---

## Related

- [Multi-Destination Backups](./multi-destination.md)
- [Hash Lists](./hash-lists.md)
- [Options](./options.md)
- [Stop](./stop.md)
