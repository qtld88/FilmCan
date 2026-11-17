# Architecture Overview

FilmCan is a **local macOS app**. No backend, no database, no telemetry. The only
outbound traffic is opt-in: ntfy / webhook notifications and the updater.

_Last checked against the code: 2026-11-17 (`main` after `cb1ad31`, sessions 1–5 of the audit merged)._

---

## Core Layers

**Views (SwiftUI)**
UI components only. Layout and user interaction.
Examples: `DestinationListView`, `InlineFanOutProgress` (per-destination progress row: two-color bar, percent, bytes/speed/ETA pills), `FanOutProgressBar`, `FailedDestRetryPanel`, `RetryRepairSheet`, `ExFATBanner`, `AlreadyBackedUpSheet`.
Progress lives inside each destination card; there is no separate summary view.

**ViewModels**
UI state, validation, orchestration of transfer runs.
Examples: `TransferViewModel`, `BackupEditorViewModel`.

**Services**
Business logic and I/O.

Copy engine:
- `CustomCopierService` — entry-point for the FilmCan fan-out engine; exposes `runCopyFanOut(...)`
- (`RsyncService` was deleted in 1.2.x; nothing shells out to rsync at runtime.)

Fan-out engine internals (`FanOutCopier`, a Swift actor):
- **Copy/verify pipeline** — `run()` filters out already-backed-up files (resume skip), then runs a copy task group (at most one file in flight per distinct source drive) that produces `CopyResult`s into a `BoundedChannel`; a single serial verify lane (`drainVerifies` → `verifySource`) consumes them, so file N is verified while file N+1 copies. **Fast** compares the hash streamed while writing, then **re-reads every destination file from disk** and compares it to the copy-time source hash. **Paranoid** does the same and also re-reads the **source** from disk. In both modes a destination that needs `F_FULLFSYNC` is re-read at least 1 s after that file was written (settle, counted from `DestWriterResult.finalizedAt`, so time spent waiting in the verify lane counts), so a drive that ignores the flush is not read back from its cache; other destinations never wait. Off copies without any check.
- `DestWriter` — one writer per (file, destination); opens a temp file with `F_NOCACHE` (write-once, keeps memory bounded), writes chunks. `finalize` refuses a temp whose byte count differs from the source (`sizeMismatch`), then `F_FULLFSYNC`/`synchronize()`, close, atomic `rename(2)`; any failure on that path removes the temp. Hash lists are written by the verify lane, not by the writer.
- **Speed/ETA** — `combinedThroughputETA` measures combined copy+verify throughput over a 30 s sliding window, then smooths it with an asymmetric EMA (slow to believe a faster rate, quick to believe a slower one); the displayed speed is that ÷ verify factor, the ETA is remaining combined work ÷ throughput.
- `BoundedChannel` — multi-producer/consumer bounded channel for backpressure between source reader and destination writers, and between the copy group and the verify lane.
- `MHLWriting` — protocol over the two hash-list writers (both actors), chosen by `config.hashListStyle`:
  - `ASCMHLWriter` — visible `<roll>/ascmhl/` folder, one manifest per generation, recorded with its C4 hash in `ascmhl_chain.xml` (`ASCMHLChain`); read back by `ASCMHLReader`
  - `SimpleMHLWriter` — hidden `<dest>/.filmcan/hashlists/<roll>.mhl`, no chain; read by `SimpleMHLReader`
- `ConflictScanner` — pre-flight: destination files that would be overwritten but are not in that destination's manifest, or whose manifested source changed (`differsFromManifest`), are resolved by `DuplicatePolicy` before any copy, never mid-copy. A plan where two files resolve to one destination path (case/normalization insensitive) stops with `duplicateTargetPaths` before any write
- `SiblingDestSource` — repair-from-sibling primitive: reads bytes from a verified neighbor, hash-verifies, atomic rename
- `DriveSpeedClassifier` — IOKit-based probe that classifies a path's volume (SSD vs HDD, USB-2/3 vs Thunderbolt vs internal, exFAT vs APFS) and reports whether `F_FULLFSYNC` is required
- `OrphanCleaner` — removes leftover `.filmcan-*` temp files in the run's roll folders and destination roots at job start, skipping temps another running job has registered
- `FileEnumerator` — recursive directory walker with macOS-junk skip list, used by both fan-out and dry-run planning

After a run:
- `CardSealService` — writes `<source>/.filmcan/seal.json` (schema 2: path + size + mtime) listing the files the engine planned, only when every planned destination holds a hash-compared copy of every one of them (`DestResult.verifiedSourcePaths`: checked this run, or skipped on resume and trusted/re-hashed); Verification Off, ignored unreadable items and the demo movie never seal; best-effort. `UnverifiedLedger` (`<roll>/.filmcan/unverified.json`) marks entries a Verification-Off run wrote, so a later verified run re-hashes them instead of skipping
- `MediaCatalogStore` — per-movie catalog of rolls (`catalog.json`); cards recognised by `CardFingerprint` (clip name + size + mtime; files ≥ 1 MiB, else ≥ 64 KiB; one whole-hour mtime shift tolerated for time-zone/DST changes on FAT32/exFAT)
- `BackupReportWriter` — PDF report with stills (AVFoundation; MXF needs Pro Video Formats); `ReportArchive` keeps a local copy; `ReportRecreation` rebuilds one later from the drive's checksum list
- `HistoryRecorder` — writes the history entry; `RepairCoordinator` — retry from source / sibling

Roll naming: `RollNumberer`, `RollIdentity` (`<roll>/.filmcan/roll.json`), `GenericCardName`, `CameraCardDetector`.

Auxiliary:
- `NotificationDispatcher`, `NotificationService`, `WebhookService` — macOS native + ntfy + webhooks (v1 per-dest, v2 aggregated). Phone push (`PhonePush`) = random topic on ntfy.sh, scanned by QR
- `KeychainStore` + `SecretsMigration` — ntfy token, webhook headers/secret in the keychain
- `ConfigurationStorage` — local persistence (`configs.json`, `presets.json`); runs `FilmPresetOwnership.migrateToFilmsOnly` once at load
- `SpeedAdviceProbe`, `NetworkSpeedProbe` — drive facts for the speed advice
- `DemoSession` — demo movie on local folders, removed by `stop`

**Utilities & Models**
Formatting, hashing (`XXH128StreamingHasher`), constants (memory caps, chunk sizes), and shared data structures (`DestProgress`, `DestResult`, `TransferResult`, `DestStatus`, `VerifyMode`, `DestFailureReason`).

---

## Persistence (Local Only)

FilmCan stores configuration, movies (each with its own organization preset), history, roll numbering and the catalog in `~/Library/Application Support/FilmCan/`. Report copies go to `ReportArchive`'s base folder. No cloud storage, no remote API. Hash lists live on each destination: ASC MHL under `<roll>/ascmhl/` (the default style) or the simple hidden `<destination>/.filmcan/hashlists/<roll>.mhl`. On the source card, FilmCan writes only `.filmcan/seal.json`. Temp files during copy use `<destination>/.filmcan-<uuid>-<basename>` and are cleaned at next job start by `OrphanCleaner`.

---

## Data Flow

### FilmCan fan-out path

1. User configures sources/destinations and runs the backup (the FilmCan Engine is the only engine)
2. `TransferViewModel.startTransfer(...)` decides the copy mode (Automatic / Parallel / Sequential) and calls `runFanOut(...)` once (all dests) or once per dest
3. `runFanOut(...)` builds one `DestWriter.Config` per destination (probing drive characteristics via `DriveSpeedClassifier`) and calls `CustomCopierService.runCopyFanOut(...)`, which instantiates a `FanOutCopier` actor and calls `run()`
4. `FanOutCopier.run()` expands all sources via `FileEnumerator`, reads the **latest manifest on disk** per destination (sealed or partial), copies each file **only to the destinations missing it** (`destsNeeding`; `forceRecopy` disables the skip), runs the writability and disk-space pre-flights and the `ConflictScanner`, then opens one hash-list writer (`MHLWriting`) per (destination, roll)
5. The copy task group reads each file once with `F_NOCACHE`, broadcasts to per-dest `BoundedChannel`s, each `DestWriter` writes + streams a hash, and produces a `CopyResult` into the verify channel. A single serial verify lane re-reads every destination from disk (Fast and Paranoid; Paranoid also re-reads the source), overlapping the next file's copy, and records each verified file in the hash list. **Stop** is honored cooperatively at every stage (see Safety guarantees for what it leaves).
6. On finalize: hash lists are closed (ASC MHL: new generation + chain entry; a cancelled run leaves a partial manifest without chain entry), per-dest results aggregated into a `TransferResult` with `destinationResults: [DestResult]`
7. Progress streams back via `DestProgress` snapshots driving each destination card's `InlineFanOutProgress`. The view clamps copy/verify bytes to a per-dest running max so concurrent emits never step the bars backward
8. If the whole backup was already present, no history card is recorded — `TransferViewModel` surfaces an `AlreadyBackedUpSheet` (with a *Verify data* button) instead
9. After success: card seal, catalog record, PDF report (if the movie has it on), notifications.
10. If any destination fails, `FailedDestRetryPanel` mounts under the transfer controls (**From source** re-runs the engine for that drive; **From sibling** copies from a verified neighbor's MHL)

### Quick Copy path (Finder)

`Services → FilmCan Copy` / Dock drop → `QuickCopyCoordinator.open(paths:)` → one
`NSWindow` + `QuickCopySession` per request. `QuickCopyFormModel` (pure) builds a
temporary `BackupConfiguration` (never stored) and a run-time `OrganizationPreset`;
the session's own `TransferViewModel(isBackgroundWorker: true)` runs it through the
normal fan-out pipeline via `startTransfer(config:organizationPresetOverride:)`.
Quick Copy offers Stop only (no Pause). Loose files: one source per selection.
When FilmCan was launched only for the quick copy, closing the last window quits it.
Quick Copy reads the picked movie's own preset and never writes it.
Spec: `docs/superpowers/specs/2026-10-15-quick-copy-design.md`.

---

## Safety guarantees (FilmCan Engine)

- **No half-written files in the destination.** All writes go to `.filmcan-*` temp files. A temp is renamed into place only when its byte count equals the source's; a source read error mid-file discards the temp and fails that file at each destination (the rest of the run continues). A flush, close or rename failure removes the temp. A hard quit or crash can still leave a temp: see Orphan cleanup.
- **Drive cache flushed before claiming success on exFAT / externals.** `F_FULLFSYNC` is invoked on the write handle; failure to honor the call is logged via `os_log` rather than swallowed.
- **No silent corruption.** Source is read once with `F_NOCACHE` so we hash bytes coming off the platter, not the OS cache. Destinations are re-read from disk in Fast and Paranoid; Paranoid also re-reads the source, and a source that cannot be re-read fails verification for that file. A destination is called verified, and a card sealed, only with a per-file hash proof (`DestResult.verifiedSourcePaths`).
- **Hash-list aggregation is race-safe.** One writer actor (`ASCMHLWriter` or `SimpleMHLWriter`) per (destination, roll); concurrent file completions serialize through the actor.
- **Orphan cleanup.** Any `.filmcan-*` left behind by a crash or hard quit is removed at the next job start.
- **Stop is clean.** Cancellation is polled cooperatively; an aborted file's writer returns before finalize, so no partial file is ever renamed into place (the temp is removed by `DestWriter.deinit`). A Stop during verification is a cancellation, not a mismatch: files already renamed but not yet verified stay at their final name, are not counted as verified and are not entered in the hash list. The run closes a **partial** manifest (no chain entry); the next run resumes from it, and an unrecorded file at its final name goes through the conflict pre-flight like any unmanifested file (Skip policy hash-compares it).
- **Memory is bounded.** Source reads and destination writes use `F_NOCACHE`, and the paranoid re-read drains its autorelease pool per chunk, so even a multi-hundred-GB offload stays within the small per-destination ring buffer (`clamp(physRAM / 128, 32 MB, 96 MB)`).

---

## Security posture

**Hardened Runtime** is enabled (`ENABLE_HARDENED_RUNTIME: YES`). This prevents code injection and library hijacking.

**Secrets** (ntfy token, webhook headers and secret) are in the keychain via `KeychainStore`. The phone-push topic is a weak secret kept in preferences on purpose, so it survives updates.

**App Sandbox is intentionally disabled.** FilmCan reads and writes arbitrary user-selected removable volumes (camera cards, external drives) and must follow symbolic links across arbitrary mount points. Sandboxing this with security-scoped bookmarks would require a significant redesign and is tracked as future work.

**`libxxhash.0.dylib` is bundled** inside `Contents/Resources/rsync/lib/<arch>/` and loaded at runtime via `dlopen` by `XXHash.swift`. The rsync binary is also bundled (arm64 + x86_64, lipo-merged for distribution) solely as the carrier for libxxhash — the rsync copy engine was removed in 1.2.x. `package_release.sh` re-signs all nested binaries and dylibs with the release identity (self-signed `FilmCan Release`, ad-hoc fallback). The DMG is **not notarized** — see `docs/release.md`.
