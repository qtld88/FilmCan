# FilmCan — Agent Instructions

## What This Is

macOS SwiftUI app for automated camera card backup. Single copy engine: the **FilmCan Engine** (`CustomCopierService`, the fan-out copier) — Swift-only, no external dependencies. The rsync engine was fully removed in 1.2.x; FilmCan no longer requires or bundles Homebrew rsync. macOS 13+, Swift 5.9, Xcode 15+.

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

## Key Commands

| Action | Command |
|--------|---------|
| Build/Run | Open `.xcodeproj` → Cmd+R |
| Regenerate project | `xcodegen generate` (run in `FilmCan/`) |
| Release build | `FilmCan/scripts/package_release.sh` (universal binary + customized DMG) |
| QA checklist | `docs/qa.md` (manual tests — no automated test suite exists) |

## Architecture Notes

- **Single copy engine**: `CustomCopierService` (the FilmCan Engine — Swift-only, no external deps), driving the `FanOutCopier` actor. Supports pause/resume and duplicate detection. The rsync engine (`RsyncService`) was fully removed in 1.2.x; no Homebrew rsync dependency remains.
- **Fan-out engine**: `FanOutCopier` (Swift actor) handles N-sources → M-destinations in one pass. One `BoundedChannel<Chunk>` per destination; source is read once and broadcast. Paranoid verify re-reads both source and dest from disk with `F_NOCACHE`. See `docs/architecture.md`.
- **Entry point**: `FilmCanApp.swift` — creates `MainView` window and `SettingsView`. No storyboards.
- **No CI, no linter, no formatter, no pre-commit hooks** — bare Xcode project.
- **Automated tests**: `FilmCan/Tests/` — `FanOutCopierIntegrationTests` (verify-bar monotonicity, real disk I/O) and `ExplodeFanOutResultTests`. No mocks — tests hit real temp dirs.
- **State pattern**: `@StateObject` in views, `@Published` in ObservableObjects. `TransferViewModel` is the single source of truth for backup runs.

## Fan-Out Engine — Key Details

- `FanOutCopier` is a Swift **actor**; all mutable state (`completedFilesByDest`, `verifiedFilesByDest`, `verifiedBytesByDest`) is actor-isolated.
- `DestWriterResult.writtenFilePath` carries the **exact written path** (accounting for organization presets). Use this — never reconstruct the path from `destPath + rootName`.
- **Verify bar monotonicity**: each writer task snapshots `verifiedAtStart = await verifiedBytesForDest(dest)` before copy starts. Copy-phase progress emits carry this value so the verify bar never resets to 0% during the next file's copy.
- **Disk space pre-flight**: `FanOutCopier.run()` checks `volumeAvailableCapacityForImportantUsage` per dest before touching any file. Throws `Error.insufficientSpace` with a user-friendly message.
- **Paranoid verify on F_FULLFSYNC drives**: 1s settle delay before re-read to prevent false hash mismatches on drives that don't honor `F_FULLFSYNC` (exFAT USB, some SD cards).
- **Fan-out result explosion**: `TransferViewModel.explodeFanOutResult` converts one aggregate `TransferResult{destinationResults:[N]}` into N per-dest records so history and notifications show correct ✓/✗ per destination.
- **Organization preset**: `FanOutCopier.Configuration` carries `organizationPreset` and `copyFolderContents`. Path resolution uses `OrganizationTemplate.resolve` in `processSource` per writer task.

## Fan-Out UI Components

| Component | File | Purpose |
|-----------|------|---------|
| `FanOutProgressBar` | `Views/Components/FanOutProgressBar.swift` | Two-color bar: copy=yellow fill, verify=green overlay (Offshoot-style) |
| `InlineFanOutProgress` | `Views/Components/InlineFanOutProgress.swift` | Per-dest progress row: bar + speed + ETA + current file + status badge |
| `FailedDestRetryPanel` | `Views/Components/FailedDestRetryPanel.swift` | Retry sheet after partial fan-out failure |
| `ExFATBanner` | in `DestinationListView.swift` | Warning banner when exFAT/F_FULLFSYNC destination detected |

Progress is mounted **inside each destination card** in `DestinationListView` — not in a separate block below.

## Known Technical Debt (docs/technical-debt.md)

1. Progress/verification state scattered across services
2. Duplicate detection branches intertwined in the FilmCan Engine path
3. CustomCopierService / FanOutCopier complexity (single responsibility concerns)
4. HistoryView mixes data logic and UI rendering
5. Drive refresh timing is nondeterministic
6. Log/hashlist lifecycle spread across multiple components
7. The rsync engine (`RsyncService`) has now been fully removed; FilmCan no longer bundles or requires Homebrew rsync. (`MultiDestSummaryView` dead code was removed in 1.2.0.)

## Conventions

- SwiftUI with MVVM — views stay thin, logic in ViewModels/Services
- No generated code beyond XcodeGen's project file
- Privacy-sensitive APIs (camera, removable storage) — entitlements in `FilmCan.entitlements`
- Release script creates notarized universal binary (arm64 + x86_64)
- Docs are in `docs/` — `architecture.md`, `technical-debt.md`, `qa.md`, `contributing.md`
