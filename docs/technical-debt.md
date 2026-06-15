# Technical Debt & Cleanup Plan

This document tracks known weak spots and a plan to improve them, based on the
current codebase. As of 1.2.0 the **FilmCan Engine (fan-out copier) is the only
user-facing copy engine** — rsync was retired from the UI; see the dead-code note
below.

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

7. **Dead / dormant code**
   - `MultiDestSummaryView` is dead code — the live progress path is
     `InlineFanOutProgress` mounted inside each destination card. Safe to remove
     now that the fan-out path has shipped (1.2.0).
   - The rsync engine (`RsyncService`, rsync `preBuildScripts` bundling, the
     `copyEngine` enum) is retained but unreachable: `RsyncOptions.copyEngine` is
     force-coerced to `.custom` on decode. Decide whether to delete it outright or
     keep it behind an explicit developer flag.

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

6. **Remove dead/dormant code**
   - Delete `MultiDestSummaryView`.
   - Decide rsync’s fate (delete vs. dev-flag) and stop bundling rsync in the
     release build if it’s removed.
