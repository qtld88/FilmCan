# Architecture Overview

FilmCan is a **local macOS app**. No backend, no database, no telemetry.

---

## Core Layers

**Views (SwiftUI)**
UI components only. Layout and user interaction.
Examples: `DestinationListView`, `MultiDestSummaryView`, `FailedDestRetryPanel`, `RetryRepairSheet`, `ExFATBanner`.

**ViewModels**
UI state, validation, orchestration of transfer runs.
Examples: `TransferViewModel`, `BackupEditorViewModel`.

**Services**
Business logic and I/O.

Copy engines:
- `RsyncService` — rsync wrapper (legacy, still default for incremental sync)
- `CustomCopierService` — entry-point for the FilmCan fan-out engine; exposes `runCopyFanOut(...)`

Fan-out engine internals:
- `FanOutCopier` — actor that orchestrates per-source planning, per-destination writer tasks, and verify
- `DestWriter` — one writer task per destination; opens a temp file with `F_NOCACHE`, writes chunks, `F_FULLFSYNC` on flush when required, atomic `rename(2)` on finalize
- `BoundedChannel` — multi-producer/consumer bounded channel for backpressure between source reader and destination writers
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

### rsync path

1. User configures sources/destinations in the UI
2. `TransferViewModel` validates paths and dispatches one `RsyncService` per destination (sequential or parallel)
3. rsync stdout is parsed for progress, verification runs post-copy when enabled
4. Results and history are stored locally and shown in the UI

### FilmCan fan-out path

1. User configures sources/destinations, picks **FilmCan Engine** as copy engine
2. `TransferViewModel.runFanOut(...)` builds one `DestWriter.Config` per destination, probing each path's drive characteristics via `DriveSpeedClassifier`
3. `CustomCopierService.runCopyFanOut(...)` instantiates a `FanOutCopier` actor and calls `run()`
4. `FanOutCopier` expands all sources into a flat plan of files via `FileEnumerator`, opens one shared `MHLWriter` per (destination, source-root), then iterates files with concurrency capped by the count of distinct source physical drives
5. For each file: one reader task pulls chunks with `F_NOCACHE`, broadcasts to per-dest `BoundedChannel`s, each `DestWriter` writes + streams a hash. After the copy, if `verifyMode == .paranoid`, every destination is re-read from disk and re-hashed, and the source is re-read once to compare
6. On finalize: shared MHLs are sealed (`<sealed/>` trailer), per-dest results aggregated into a `TransferResult` with `destinationResults: [DestResult]`
7. Progress is streamed back via `DestProgress` snapshots that drive `MultiDestSummaryView`'s per-dest tiles. The legacy `destinationProgress` dict is also updated (blended copy + verify) so older views stay coherent
8. If any destination fails, `FailedDestRetryPanel` mounts under the transfer controls. The user picks **From source** (re-runs fan-out for just that drive) or **From sibling** (`SiblingDestSource` reads the verified neighbor's MHL and re-copies file by file)

---

## Safety guarantees (FilmCan Engine)

- **No half-written files in the destination.** All writes go to `.filmcan-*` temp files; atomic `rename(2)` on success.
- **Drive cache flushed before claiming success on exFAT / externals.** `F_FULLFSYNC` is invoked on the write handle; failure to honor the call is logged via `os_log` rather than swallowed.
- **No silent corruption.** Source is read once with `F_NOCACHE` so we hash bytes coming off the platter, not the OS cache. Destinations are re-read from disk in paranoid mode to defeat firmware cache lies.
- **MHL aggregation is race-safe.** One shared `MHLWriter` actor per (destination, source-root); concurrent file completions serialize through the actor and aggregate into a single sealed MHL.
- **Orphan cleanup.** Any `.filmcan-*` left behind by a crash or hard quit is removed at the next job start.
