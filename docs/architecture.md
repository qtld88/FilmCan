# Architecture Overview

FilmCan is a **local macOS app**. No backend, no database, no telemetry.

---

## Core Layers

**Views (SwiftUI)**
UI components only. Layout and user interaction.
Examples: `DestinationListView`, `InlineFanOutProgress` (per-destination progress row: two-color bar, percent, bytes/speed/ETA pills), `FanOutProgressBar`, `FailedDestRetryPanel`, `RetryRepairSheet`, `ExFATBanner`, `AlreadyBackedUpSheet`.
(`MultiDestSummaryView` is deprecated dead code, superseded by the inline per-card progress.)

**ViewModels**
UI state, validation, orchestration of transfer runs.
Examples: `TransferViewModel`, `BackupEditorViewModel`.

**Services**
Business logic and I/O.

Copy engine:
- `CustomCopierService` — entry-point for the FilmCan fan-out engine; exposes `runCopyFanOut(...)`
- `RsyncService` — rsync wrapper, **retired from the UI in 1.2.0** (no longer selectable; code remains but is unreachable)

Fan-out engine internals (`FanOutCopier`, a Swift actor):
- **Copy/verify pipeline** — `run()` filters out already-backed-up files (resume skip), then runs a copy task group that produces `CopyResult`s into a `BoundedChannel`; a single serial verify lane (`drainVerifies` → `verifySource`) consumes them, so file N is verified while file N+1 copies.
- `DestWriter` — one writer task per destination; opens a temp file with `F_NOCACHE` (write-once, keeps memory bounded), writes chunks, `F_FULLFSYNC`/`synchronize()` on finalize, atomic `rename(2)`.
- **Speed/ETA** — `combinedThroughputETA` computes a moving-average (~10s window) of combined copy+verify throughput; the displayed speed is that ÷ verify factor, the ETA is remaining combined work ÷ throughput (stable and honest from the first seconds).
- `BoundedChannel` — multi-producer/consumer bounded channel for backpressure between source reader and destination writers, and between the copy group and the verify lane.
- `MHLWriter` — actor that aggregates `<hash>` entries per (destination, source root) and seals the file at job end
- `MHLReader` — XML parser for cinema-format MHL hash lists
- `SiblingDestSource` — repair-from-sibling primitive: reads bytes from a verified neighbor, hash-verifies, atomic rename
- `DriveSpeedClassifier` — IOKit-based probe that classifies a path's volume (SSD vs HDD, USB-2/3 vs Thunderbolt vs internal, exFAT vs APFS) and reports whether `F_FULLFSYNC` is required
- `OrphanCleaner` — removes leftover `.filmcan-*` temp files at job start
- `FileEnumerator` — recursive directory walker with macOS-junk skip list, used by both fan-out and dry-run planning

Auxiliary:
- `NotificationService`, `WebhookService` — macOS native + ntfy + webhooks (v1 per-dest, v2 aggregated)
- `ConfigurationStorage` — local persistence

**Utilities & Models**
Formatting, hashing (`XXH128StreamingHasher`), constants (memory caps, chunk sizes), and shared data structures (`DestProgress`, `DestResult`, `TransferResult`, `DestStatus`, `VerifyMode`, `DestFailureReason`).

---

## Persistence (Local Only)

FilmCan stores configuration, presets, and history in the user's **Application Support** folder. No cloud storage, no remote API. MHL files are written into each destination drive at `<destination>/.filmcan/hashlists/<sourceRoot>.mhl`. Temp files during copy use `<destination>/.filmcan-<uuid>-<basename>` and are cleaned at next job start by `OrphanCleaner`.

---

## Data Flow

### FilmCan fan-out path

1. User configures sources/destinations and runs the backup (the FilmCan Engine is the only engine)
2. `TransferViewModel.startTransfer(...)` decides the copy mode (Automatic / Parallel / Sequential) and calls `runFanOut(...)` once (all dests) or once per dest
3. `runFanOut(...)` builds one `DestWriter.Config` per destination (probing drive characteristics via `DriveSpeedClassifier`) and calls `CustomCopierService.runCopyFanOut(...)`, which instantiates a `FanOutCopier` actor and calls `run()`
4. `FanOutCopier.run()` expands all sources via `FileEnumerator`, **drops files already recorded in every destination's MHL and still present on disk** (resume skip; `forceRecopy` disables it), runs a disk-space pre-flight, then opens one shared `MHLWriter` per (destination, source-root), **seeded with existing entries** so a resumed run appends instead of truncating
5. The copy task group reads each file once with `F_NOCACHE`, broadcasts to per-dest `BoundedChannel`s, each `DestWriter` writes + streams a hash, and produces a `CopyResult` into the verify channel. A single serial verify lane re-reads (paranoid) or stream-checks (fast) each destination, overlapping the next file's copy. **Stop** is honored cooperatively at every stage with no partial files left behind.
6. On finalize: shared MHLs are sealed, per-dest results aggregated into a `TransferResult` with `destinationResults: [DestResult]`
7. Progress streams back via `DestProgress` snapshots driving each destination card's `InlineFanOutProgress`. The view clamps copy/verify bytes to a per-dest running max so concurrent emits never step the bars backward
8. If the whole backup was already present, no history card is recorded — `TransferViewModel` surfaces an `AlreadyBackedUpSheet` (with a *Verify data* button) instead
9. If any destination fails, `FailedDestRetryPanel` mounts under the transfer controls (**From source** re-runs the engine for that drive; **From sibling** copies from a verified neighbor's MHL)

---

## Safety guarantees (FilmCan Engine)

- **No half-written files in the destination.** All writes go to `.filmcan-*` temp files; atomic `rename(2)` on success.
- **Drive cache flushed before claiming success on exFAT / externals.** `F_FULLFSYNC` is invoked on the write handle; failure to honor the call is logged via `os_log` rather than swallowed.
- **No silent corruption.** Source is read once with `F_NOCACHE` so we hash bytes coming off the platter, not the OS cache. Destinations are re-read from disk in paranoid mode to defeat firmware cache lies.
- **MHL aggregation is race-safe.** One shared `MHLWriter` actor per (destination, source-root); concurrent file completions serialize through the actor and aggregate into a single sealed MHL.
- **Orphan cleanup.** Any `.filmcan-*` left behind by a crash or hard quit is removed at the next job start.
- **Stop is clean.** Cancellation is polled cooperatively; an aborted file's writer returns before finalize, so no partial file is ever renamed into place (the temp is removed by `DestWriter.deinit`). The verify lane skips remaining work and marks affected destinations cancelled.
- **Memory is bounded.** Source reads and destination writes use `F_NOCACHE`, and the paranoid re-read drains its autorelease pool per chunk, so even a multi-hundred-GB offload stays within the small per-destination ring buffer (`clamp(physRAM / 128, 32 MB, 96 MB)`).
