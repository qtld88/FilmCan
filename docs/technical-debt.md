# Technical Debt & Cleanup Plan

This document tracks known weak spots and a plan to improve them, based on the current codebase.

---

## Known Weak Areas

1. **Progress + verification state**
   - Progress is computed across multiple places (transfer state, destination presentation, verification bytes).
   - Multi‑destination + verification makes status/ETA logic hard to reason about.

2. **Duplicate handling + hash list verification**
   - Duplicate policy logic is spread across rsync and FilmCan Engine paths.
   - “Verify using hash list” behaves differently depending on hash list availability.

3. **Custom copier complexity**
   - Copy, verify, hash list, and duplicate policies are intertwined.
   - Many branches (skip/overwrite/verify/ask) make regressions easy.

4. **History rendering + logic**
   - Transfer history view owns filtering, sorting, formatting, and verification UI.
   - Log parsing for counts happens inside the view flow.

5. **Drive refresh + auto‑detect**
   - Drive list refresh is time‑based and notification‑based.
   - Auto‑detect behavior depends on refresh timing and can be nondeterministic.

6. **Log + hash list lifecycle**
   - Log creation and warnings are spread across multiple paths.
   - Hash list creation happens in rsync, FilmCan Engine, and fallback generation.

---

## Cleanup Plan (Short)

1. **Add focused tests**
   - Organization template token resolution.
   - Duplicate policy outcomes (skip/overwrite/add counter/verify/ask) for both engines.
   - Hash list naming + write/failure behavior.
   - rsync error parsing and messaging.

2. **Centralize progress computation**
   - Single progress model that feeds UI status, percent, and ETA.
   - Clear separation between copy progress and verification progress.

3. **Extract history view model**
   - Move filtering/sorting/formatting out of the view.
   - Make verification UI use a dedicated model or service.

4. **Unify drive refresh + auto‑detect**
   - One refresh path with explicit triggers.
   - Deterministic auto‑detect results for tests.

5. **Single source of truth for logs + hash lists**
   - One place for log creation + failure messaging.
   - One place for hash list creation + failure messaging.
