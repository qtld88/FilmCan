# FilmCan — Agent Instructions

## What This Is

macOS SwiftUI app for automated camera card backup. Single copy engine: the **FilmCan Engine** (`CustomCopierService`, the fan-out copier) — Swift-only. The rsync engine (code + UI) was removed in 1.2.x; `RsyncOptions`/`CopyEngine` models replaced by `EngineOptions`/`DefaultExcludes` in 1.3.x. Note: the build still bundles the rsync binary **only** because its libs ship `libxxhash.0.dylib`, which `XXHash.swift` dlopen's for xxh128 verification (`Resources/rsync/lib/<arch>/`). Dropping the rsync binary requires vendoring just libxxhash first (tracked in technical-debt). macOS 13+, Swift 5.9, Xcode 15+.

## Quick Start

```
open FilmCan/FilmCan.xcodeproj   # XcodeGen-generated — do not edit the .xcodeproj directly
```

After editing `project.yml`: `xcodegen generate` then reopen.

## Project Structure

```
FilmCan/Sources/
├── App/             # FilmCanApp.swift (@main entry), MainView, SettingsView
├── Views/           # All SwiftUI views (tabs: Backup, History, Settings, About)
├── ViewModels/      # ObservableObjects, especially TaskState
├── Services/        # CustomCopierService, NotificationService, WebhookService, etc.
├── Models/          # DriveInfo, TaskResult, Preset, HistoryEntry, etc.
├── Utilities/       # Logger, HashListGenerator, DiskArbitration helpers
└── Resources/       # Assets, entitlements
```

Local data lives in `~/Application Support`.

`FilmCan/build/` (DerivedData) and `FilmCan/dist/` (staged .app, DMG) are local build artifacts — exclude them from searches.

## Key Commands

| Action | Command |
|--------|---------|
| Build/Run | Open `.xcodeproj` → Cmd+R |
| Regenerate project | `xcodegen generate` (run in `FilmCan/`) |
| Release build | `FilmCan/scripts/package_release.sh` (universal binary + customized DMG) |
| Run tests | Xcode Cmd+U (`FilmCanTests` target). No shared scheme is committed — `xcodebuild test` only works after Xcode auto-generates one |
| QA checklist | `docs/qa.md` + `docs/smoke-qa-checklist.md` (manual passes, complement the automated suite) |

## Architecture Notes

- **Single copy engine**: `CustomCopierService` (the FilmCan Engine — Swift-only, no external deps), driving the `FanOutCopier` actor. Supports pause/resume and duplicate detection. The rsync engine (`RsyncService`) was fully removed in 1.2.x — nothing shells out to rsync at runtime. **Build-time**, Homebrew rsync ≥ 3.4.0 is still required: the "Embed rsync" phase in `project.yml` harvests the binary + dylibs (incl. `libxxhash.0.dylib`) into `Resources/rsync/`.
- **Fan-out engine**: `FanOutCopier` (Swift actor) handles N-sources → M-destinations in one pass. One `BoundedChannel<Chunk>` per destination; source is read once and broadcast. Paranoid verify re-reads both source and dest from disk with `F_NOCACHE`. See `docs/architecture.md`.
- **Entry point**: `FilmCanApp.swift` — creates `MainView` window and `SettingsView`. No storyboards.
- **No CI, no linter, no formatter, no pre-commit hooks** — bare Xcode project.
- **Automated tests**: `FilmCan/Tests/` (~100 tests, real temp-dir disk I/O, no mocks) — `FanOutCopierIntegrationTests` (progress monotonicity, per-dest resume, sound routing, cancel/partial), `FanOutCopierSafetyTests` (cancel/unwritable), `ASCMHLWriter/Reader/Chain/Conformance` (validated against the reference `ascmhl` CLI), `C4HashTests`, `OrganizationTemplateTokenTests`.
- **State pattern**: `@StateObject` in views, `@Published` in ObservableObjects. `TransferViewModel` is the single source of truth for backup runs.

## Fan-Out Engine — Key Details

- `FanOutCopier` is a Swift **actor**; all mutable state (`completedFilesByDest`, `verifiedFilesByDest`, `verifiedBytesByDest`) is actor-isolated.
- `DestWriterResult.writtenFilePath` carries the **exact written path** (accounting for organization presets). Use this — never reconstruct the path from `destPath + rootName`.
- **Verify bar monotonicity**: each writer task snapshots `verifiedAtStart = await verifiedBytesForDest(dest)` before copy starts. Copy-phase progress emits carry this value so the verify bar never resets to 0% during the next file's copy.
- **Disk space pre-flight**: `FanOutCopier.run()` checks `DriveUtilities.liveAvailableBytes` against each dest's **needed** bytes (post-resume subset) before touching any file. Throws `Error.insufficientSpace` with a user-friendly message.
- **Paranoid verify on F_FULLFSYNC drives**: 1s settle delay before re-read to prevent false hash mismatches on drives that don't honor `F_FULLFSYNC` (exFAT USB, some SD cards).
- **Fan-out result explosion**: `TransferViewModel.explodeFanOutResult` converts one aggregate `TransferResult{destinationResults:[N]}` into N per-dest records so history and notifications show correct ✓/✗ per destination.
- **Organization preset**: `FanOutCopier.Configuration` carries `organizationPreset` and `copyFolderContents`. Path resolution uses `OrganizationTemplate.resolve` in `processSource` per writer task.
- **Per-destination resume**: a file present+recorded at one destination but missing at another is copied **only where missing** (`destsNeeding(_:)`); the up-to-date destination skips it. Per-dest `skippedByDest`/`bytesTotalByDest` drive the UI. The progress bar spans the **whole job** (already-present + this run) — the per-dest counters (`finalizedBytesByDest`, `verifiedBytesByDest`, `completedFilesByDest`) are **seeded** with the resumed portion so the bar reads e.g. 30/500 not 0/470.
- **Copy bar = finalized + current file**: `finalizedBytesByDest` counts bytes actually renamed into place (what Finder shows); the live bar adds only the *current* file's in-flight bytes. On stop, `emitCancelled` snaps every in-progress dest back to finalized. Increment uses the planned `sourceSize` (same units as the bar total) so it reaches exactly 100%.
- **Resume reads the latest manifest ON DISK** (`ASCMHLChain.latestManifestFileName`), sealed *or* partial — a cancelled run writes a partial manifest (no chain entry), so chain-only lookup would miss it. `nextSequence` also counts on-disk generations.
- **Writability preflight**: `run()` probes each destination (write+delete a `.filmcan-writeprobe`) and throws `Error.destinationUnwritable` before copying. A mid-copy write/finalize/verify failure or source corruption emits a per-dest `.failed` so the card flips red live while other dests continue.

## Netflix Ingest & Camera/Sound Routing

- **Netflix Ingest preset** (`OrganizationPreset.netflixIngest()`, name `OrganizationPreset.netflixIngestName`): camera template `{date}_{episode}_{day}_{unit}/Camera_Media/{cameraFormat}`, sound template `{date}_{episode}_{day}_{unit}/Sound_Media`. Roll folder auto-appended. Scaffolds sibling `Reports/` + `Sound_Media/`. Shoot metadata = `BackupConfiguration.episode/day/unit/cameraFormat` → `ShootMetadata` tokens.
- **Camera/Sound per source**: `SourceMediaKind` (camera/sound), tagged in `BackupConfiguration.sourceMediaKinds[path]` (absent ⇒ camera). `OrganizationTemplate.resolve(…, mediaKind:)` picks the sound template for sound sources; threaded through `FanOutCopier.Configuration.sourceMediaKinds` → `resolveDestFilePath/resolveRollFolder(mediaKind:)`. Each sound roll gets its own `ascmhl/`, verify and resume — identical treatment, just under `Sound_Media/`.
- **Editable templates**: `config.cameraFolderTemplate` / `config.soundFolderTemplate` override the Netflix preset's paths (applied in `TransferViewModel.resolveOrganizationPreset`, gated to the Netflix preset). Edited in **Options › Destinations › Folder templates**.
- **Sound auto-detect**: `config.soundAutoDetectEnabled` + `soundAutoDetectPatterns`. `BackupEditorViewModel.refreshAutoDetectedSoundSources()` mirrors the camera detector — adds matching drives to sources AND tags them Sound, live on pattern/enable/drive-refresh.
- **ASC MHL**: `ASCMHLWriter` (generation-aware, lazy dir creation, skips empty generations) + `ASCMHLChain` (C4-hashed `ascmhl_chain.xml`) + `ASCMHLReader`. `MHLWriting` protocol abstracts ASC MHL vs `SimpleMHLWriter` (hidden `.filmcan/hashlists/<roll>.mhl`), chosen by `config.hashListStyle`. `NetflixNameValidator` enforces prohibited chars + unique roll names. See `docs/features/netflix-ingest.md` and `docs/reference/netflix-asc-mhl-requirements.md`.

## Fan-Out UI Components

| Component | File | Purpose |
|-----------|------|---------|
| `FanOutProgressBar` | `Views/Components/FanOutProgressBar.swift` | Two-color bar: copy=yellow fill, verify=green overlay (Offshoot-style) |
| `InlineFanOutProgress` | `Views/Components/InlineFanOutProgress.swift` | Per-dest progress row: bar + speed + ETA + current file + status badge |
| `FailedDestRetryPanel` | `Views/Components/FailedDestRetryPanel.swift` | Retry sheet after partial fan-out failure |
| `ExFATBanner` | in `DestinationListView.swift` | Warning banner when exFAT/F_FULLFSYNC destination detected |

Progress is mounted **inside each destination card** in `DestinationListView` — not in a separate block below.

## Known Technical Debt

`docs/technical-debt.md` is canonical — read it there, don't trust summaries copied elsewhere (this file's copy drifted once already). Headline areas: progress/verification state scattered, duplicate-detection branches intertwined, CustomCopierService/FanOutCopier complexity, HistoryView mixing logic and UI, nondeterministic drive refresh, log/hashlist lifecycle spread, dormant code.

## Conventions

- SwiftUI with MVVM — views stay thin, logic in ViewModels/Services
- No generated code beyond XcodeGen's project file
- Privacy-sensitive APIs (camera, removable storage) — entitlements in `FilmCan.entitlements`
- Release script (`scripts/package_release.sh`) creates a universal DMG (arm64 + x86_64), **ad-hoc codesigned only — NOT notarized** (no Apple creds or network needed; downloaders must right-click→Open past Gatekeeper)
- Docs are in `docs/` — `architecture.md`, `technical-debt.md`, `qa.md`, `contributing.md`
