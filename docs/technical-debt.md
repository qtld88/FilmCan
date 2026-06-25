# Technical Debt & Cleanup Plan

This document tracks known weak spots and a plan to improve them, based on the
current codebase. As of 1.2.x the **FilmCan Engine (fan-out copier) is the only
copy engine** — the rsync engine code + UI were removed and FilmCan no longer
requires Homebrew rsync. (The build still bundles the rsync binary solely to ship
`libxxhash` for verification — see item 7.)

---

## Known Weak Areas

1. **Progress + verification state**
   - Progress is computed across multiple places (transfer state, destination
     presentation, per-dest verify bytes in `FanOutCopier`).
   - Multi-destination + the copy/verify pipeline makes status/ETA logic hard to
     reason about; the combined-throughput ETA lives alongside legacy per-dest
     progress merging in `TransferViewModel`.

2. **Duplicate handling + hash list verification**
   - Duplicate policy branches (skip / overwrite / add counter / ask) are
     intertwined with copy and verify in the FilmCan Engine path.
   - “Verify using hash list” behaves differently depending on MHL availability.

3. **CustomCopierService / FanOutCopier complexity**
   - Copy, verify, hash list, resume-skip, and duplicate policy are intertwined
     in one actor with many branches, making regressions easy.
   - Single-responsibility concerns: `FanOutCopier.run()` does preflight, MHL
     seeding, resume filtering, pipelining, and result explosion.

4. **History rendering + logic**
   - Transfer history view owns filtering, sorting, formatting, and verification UI.
   - Log parsing for counts happens inside the view flow.

5. **Drive refresh + auto-detect**
   - Drive list refresh is time-based and notification-based.
   - Auto-detect behavior depends on refresh timing and can be nondeterministic.

6. **Log + hash list lifecycle**
   - Log creation and warnings are spread across multiple paths.
   - Hash list creation happens in the FilmCan Engine and in fallback generation.

7. **Dormant code**
   - `MultiDestSummaryView` (dead) was removed in 1.2.0; the live progress path is
     `InlineFanOutProgress` mounted inside each destination card.
   - **rsync engine code + UI removed in 1.2.x** (`RsyncService`, the engine picker,
     the "Transfer refinements" tab, engine-help sheet). **Also done:** `RsyncOptions`
     and `CopyEngine` models replaced by `EngineOptions` (live fields only) and
     `DefaultExcludes` (1.3.x). **Remaining:** the build still bundles the rsync
     binary + libs because `XXHash.swift` dlopen's `libxxhash.0.dylib` from
     `Resources/rsync/lib/<arch>/` for xxh128 verification (no pure-Swift fallback —
     `StreamingHasher` returns nil if it can't load). To stop bundling rsync, vendor
     `libxxhash.0.dylib` standalone (own embed step + update
     `XXHash.possibleLibraryPaths`) first, then drop the rsync embed.

---

## Cleanup Plan (Short)

1. **Add focused tests**
   - Organization template token resolution.
   - Duplicate policy outcomes (skip / overwrite / add counter / ask) for the
     FilmCan Engine.
   - Resume-skip: MHL-recorded + present → skipped; deleted-from-dest → re-copied;
     Force re-copy bypass.
   - Hash list naming + write/failure behavior.

2. **Centralize progress computation**
   - Single progress model that feeds UI status, percent, speed, and ETA.
   - Clear separation between copy progress and verification progress (today split
     between `FanOutCopier` emits and `TransferViewModel` merging).

3. **Extract history view model**
   - Move filtering/sorting/formatting out of the view.
   - Make verification UI use a dedicated model or service.

4. **Unify drive refresh + auto-detect**
   - One refresh path with explicit triggers.
   - Deterministic auto-detect results for tests.

5. **Single source of truth for logs + hash lists**
   - One place for log creation + failure messaging.
   - One place for hash list creation + failure messaging.

6. **Remove dormant code**
   - ~~Delete `MultiDestSummaryView`.~~ Done in 1.2.0.
   - ~~Delete the rsync engine code + UI.~~ Done in 1.2.x.
   - **Still TODO:** vendor `libxxhash.0.dylib` standalone, then stop bundling the
     rsync binary (see Known Weak Areas #7).

7. **BackupEditor options god-view — nav-speed bottleneck** (found 2026-06-24)
   - The remaining UI lag (Destinations Options card slow to open; first open of a
     never-opened Film tab slow; periodic stalls) is **SwiftUI view-body
     construction + layout on the main thread**, not disk. Confirmed with the
     DEBUG `MainThreadWatchdog` + `PerfSignpost` harness: every residual stall is
     `region='idle'` (outside the instrumented drive/list regions), ~100–550ms.
   - Causes: `BackupEditorView+Options.swift` is a ~1500-line god-view; the
     Destinations tab (`destinationsContent`/`organizationOptionsContent`) is a
     large always-mounted tree (TextEditors, two token grids, disclosure groups);
     `MainView.swift:153` puts `.id(config.id)` on the editor (full teardown +
     rebuild per tab switch); `MainView.swift:39` posts `.filmCanDriveListChanged`
     every 6s → `refreshAllDriveData` → full editor re-render.
   - Fix direction (needs its own spec/plan — do NOT hack inline): decompose the
     god-view into small `Equatable` subviews so SwiftUI skips unchanged subtrees;
     lazy-build/gate the heavy organization editor; reconsider `.id(config.id)`
     and the 6s blanket refresh.
   - Tool already in place: the `MainThreadWatchdog`/`PerfSignpost` harness
     (DEBUG-only) on the `perf/nav-speed-audit` branch — reuse it to attribute and
     verify the decomposition. Disk-side wins (DriveInfoCache) already landed.
