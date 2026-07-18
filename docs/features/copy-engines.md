# Copy Engine

FilmCan copies with one purpose-built engine: the **FilmCan Engine**, a fan-out
copier designed for cinema rushes, read the source once, write to every
destination at once, verify with cinema-grade hash lists, and recover a failed
drive with one click.

---

## How it works

1. **Read source once.** A single read pipeline pulls each file from the card
   with `F_NOCACHE`, bytes come straight off the device, not the OS cache, and
   a huge offload doesn't fill RAM with cached source data.
2. **Broadcast to every destination at once.** One bounded channel feeds a
   writer task per drive. The slowest drive sets the pace; faster drives idle
   briefly. Destination writes also use `F_NOCACHE` so a multi-hundred-GB copy
   stays memory-bounded.
3. **Honest writes.** On exFAT / external / USB drives, `F_FULLFSYNC` is invoked
   at finalize so the drive's onboard cache is flushed to media before the file
   is claimed done. Internal APFS uses a regular `synchronize()`.
4. **Atomic finalize.** Each file is written to a hidden `.filmcan-<uuid>-<name>`
   temp file, then `rename(2)`'d into place, never a half-written file at the
   destination.
5. **Verify** (see modes below), overlapping the copy of the next file.
6. **MHL per source root.** One sealed ASC-format `.mhl` per source root,
   aggregating every file in that tree, at `<dest>/.filmcan/hashlists/<root>.mhl`.

### Verify pipeline

Verification runs on its own lane **while the next file is still copying**, so a
paranoid re-read no longer roughly doubles the wall time, it mostly hides behind
the copy. Only the last file's verify tail runs alone (shown as "Verifying…").

---

## Verification modes

Pick in **Backup Editor → Options → Verification**.

| Mode | Catches | Cost |
|---|---|---|
| **Off** | nothing | fastest, no hashing or checking |
| **Fast** *(default for new projects)* | RAM bit-flips, PCI/USB corruption, partial writes, via the hash computed during the copy | none beyond the copy; no re-read |
| **Paranoid** | all of Fast **+** drive-firmware silent corruption, OS-cache lies, bit rot at rest, re-reads every destination (and the source) from disk and re-hashes | extra disk I/O, mostly overlapped with copying |

For rushes from a master card you can't re-shoot, use **Paranoid**.

---

## Resume, re-running skips what's already there

Re-running a backup (including after **Stop**) does **not** recopy files that are
already done. A file is skipped when it is recorded in **every** destination's
hash list **and** still present on disk there. Only the remaining files are
copied; the progress row reads *"Resuming, N already backed up, copying the
rest."*

- If the whole backup is already present, no history card is added, an **Already
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

- **Memory-bounded.** Source reads and destination writes bypass the OS cache
  (`F_NOCACHE`); the paranoid re-read drains its autorelease pool per chunk.
  In-flight memory is just the per-destination ring buffer, clamped to
  `clamp(physRAM / 128, 32 MB, 96 MB)`.
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
