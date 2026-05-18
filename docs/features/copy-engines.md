# Copy Engines

FilmCan offers two copy engines:

- **rsync** — mature, flexible, supports incremental sync and custom filters
- **FilmCan Engine** — fan-out copy purpose-built for cinema rushes, with paranoid verification, cinema-grade hash lists, and one-click sibling repair

Pick **FilmCan Engine** for fresh card offloads to multiple drives. Pick **rsync** when you need incremental sync or custom rsync flags.

---

## FilmCan Engine (fan-out)

### How it works

1. **Read source once.** A single read pipeline pulls each file from the card, bypassing the macOS Unified Buffer Cache via `F_NOCACHE`.
2. **Broadcast to every destination in parallel.** Bounded channels feed one writer task per drive. No serial bottleneck — slowest drive sets the pace, fastest drives idle briefly.
3. **Honest writes.** On exFAT and external/USB drives, `F_FULLFSYNC` is invoked so the drive's onboard cache is flushed to media before finalize. On internal APFS, a regular `fsync` is enough.
4. **Atomic finalize.** Each file is written to a hidden `.filmcan-<uuid>-<name>` temp file, then `rename(2)`'d into place. No half-written files in the destination.
5. **Verify.**
   - **Fast mode** — stream hash computed during the copy is checked against the source hash. Catches RAM/PCI/bus corruption.
   - **Paranoid mode** — after the copy, every destination is **re-read from disk**, hashed again, and compared to a fresh re-read of the source. Catches drive-firmware silent corruption, cache lies, and bit rot that just happened.
6. **MHL per source root.** One ASC-format `.mhl` per source root, aggregated across every file in that tree, sealed with `<sealed/>` at job end. Stored at `<dest>/.filmcan/hashlists/<root>.mhl`.

### Directory sources

Drop a mounted card (e.g. `/Volumes/A001_C002`) or any folder. FilmCan recursively walks the tree, mirrors the layout under each destination as `<dest>/<rootName>/<relativePath>`, and aggregates one MHL per source root. Subdirectories preserve nesting. Hidden macOS junk (`.Spotlight-V100`, `.fseventsd`, `.DS_Store`) is skipped automatically.

### Failed drives — one-click repair

When a drive fails mid-copy or fails verify, a **Retry** button appears on its row. Pressing it opens the repair sheet with two choices:

- **From source** — re-runs the fan-out engine for that single drive only, pulling from the original source(s) if still mounted.
- **From sibling** — reads files from a verified neighbor drive's MHL list, copies them to the failed drive, and hash-verifies each one. The card no longer needs to be mounted. Cinema set workflow: keep going, fix the drive at lunch.

The repair flow only enables the **From sibling** option when at least one other destination from the same job succeeded.

### Verify modes — when to pick which

| Mode | Catches | Cost |
|---|---|---|
| **Fast** | RAM bit-flips, PCI/USB corruption, partial writes | ~0% (hash computed during copy anyway) |
| **Paranoid** | All of fast + drive-firmware silent corruption, OS cache lies, bit rot at rest | Adds one full re-read of source and every dest after copy. ~2× wall time on a 1:1 copy, less on multi-dest jobs because dest re-reads parallelize. |

For rushes from a master card you can't re-shoot, use **paranoid**. Default is **paranoid**.

### Performance characteristics

- **Multi-source concurrency** capped to the number of distinct source physical drives — copying three clips from one card runs sequentially per source (no head-thrashing), but copying from card-A and card-B at once runs in parallel.
- **Memory ceiling** — per-destination ring buffer clamped to `clamp(physRAM / 32, 64 MB, 256 MB)`. Three destinations on a 32 GB Mac = ~768 MB max copy buffer.
- **Chunk size** picked by classifying the slowest destination's bus (USB-2 vs USB-3 vs Thunderbolt vs internal) — 4 MB on slow buses, up to 16 MB on Thunderbolt and internal.

### Limitations

- No incremental sync — always copies the full selection.
- No custom flags / filters (rsync only).
- Resume after a pause is not supported (rsync only).
- Lots of tiny files (thousands of KB-scale) are slower than rsync's reflink-aware paths.

---

## rsync

### How it works

1. rsync copies files using its own incremental algorithm.
2. Optional post-copy verification (`--checksum`).
3. Hash lists generated during copy when verification is enabled.

### Use when you need

- **Incremental sync** — re-runs only copy changed files.
- **Resume** — pick up after a pause or disconnect.
- **Custom rsync arguments** — anything in the rsync man page is fair game via **Custom rsync Arguments**.
- **Compatibility with existing rsync-based pipelines** (DIT carts, post-house ingest).

---

## Which Should I Use?

| Use case | Engine |
|---|---|
| Fresh card offload to 2+ drives | **FilmCan Engine** (fan-out is the win) |
| Single drive, single source, just want it fast | Either |
| Incremental re-sync of a project folder | **rsync** |
| Need exFAT/external write safety guarantees | **FilmCan Engine** (`F_FULLFSYNC`) |
| Cinema-grade MHL hash lists | **FilmCan Engine** (sealed ASC MHL per root) |
| Resume after pause / disconnect | **rsync** |
| Custom rsync flags (delete, filter, dry-run flags, etc.) | **rsync** |
| One drive failed mid-job, want to recover from neighbor | **FilmCan Engine** (sibling repair) |

---

## Related

- [Multi-Destination Backups](./multi-destination.md)
- [Hash Lists](./hash-lists.md)
- [rsync Details](./rsync.md)
- [Options](./options.md)
- [Custom rsync Arguments](./custom-rsync.md)
