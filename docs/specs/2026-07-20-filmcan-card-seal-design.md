# FilmCan — Card Seal Design

**Date:** 2026-07-20
**Status:** Approved design, pre-implementation
**Scope:** Single feature. One implementation plan.

## Problem

After a verified backup, a camera card is safe to reuse (reformat) — but nothing signals that state to the operator. Cards get accidentally reused before backup, or wiped when a backup was only partial. Prior art (Ottomatic Parashoot) forces the issue by corrupting the card's first 2 MB so the camera must reformat. That requires raw block writes (`/dev/rdiskN`, `root:operator 0640`), hence a privileged helper + notarization — a tier FilmCan does not occupy today (ad-hoc signed, not notarized, no helper).

**Decision:** implement a **signal-only** equivalent. No block writes, no root, no helper. FilmCan cannot physically force a camera reformat; it provides a trustworthy human-facing signal derived from the verified backup state.

This is understood and accepted: the camera does not read FilmCan's signal and will overwrite the card regardless. The value is operator awareness at the two moments that matter — looking at the card, and ejecting it.

## Concept — "Card Seal"

Once a backup run completes with full verification, FilmCan **seals** the source card. The seal **breaks** as soon as the card's contents change (e.g. more footage shot onto it). Three surfaces expose the same `SealState`:

1. **In-app badge** on each source card (`SourceListView`): ✓ sealed / ⚠ broken / neutral.
2. **Marker file** written to the card root (`.filmcan-seal.json`), machine-readable, camera-safe.
3. **Eject guard**: confirmation dialog when ejecting a card that is not sealed.

All three read one source of truth: `CardSealService.evaluate(source)`.

## Resolved decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| A | Marker visibility | **Hidden** `.filmcan-seal.json` at source root | Camera-safe; some cameras choke on unexpected visible files. Human visibility comes from the in-app badge + eject guard, not from a file on the card. |
| B | Eject guard hardness | **Warn + confirmation** (soft, overridable) | A hard block is hostile on set; explicit confirm preserves operator control while catching mistakes. |
| C | Multi-destination rule | Seal **only if every planned destination verified** that card's files | The seal means "safe to wipe." A partial fan-out is not safe. |
| D | Re-insertion check | **Structural** (relPath + size + mtime), no re-hash | The real hash verification already happened during backup and is recorded in the ASC MHL. Re-hashing on every insertion is too slow; offered separately as a future opt-in, out of scope here. |

## Components

### `CardSeal` (Model, Codable)

Serialized to `.filmcan-seal.json` at the source root.

```
struct CardSeal: Codable {
    let schemaVersion: Int          // bump on format change; unknown → treated as .none
    let volumeUUID: String          // identity guard against a marker copied to another card
    let sealDate: Date
    let appVersion: String
    let entries: [Entry]            // exactly the set actually backed up (post-exclude)
    let destinationsVerified: [String]
    let mhlRef: String?             // path/name of the sealing ASC MHL manifest, for traceability

    struct Entry: Codable {
        let relPath: String
        let size: Int64
        let mtime: Date
    }
}
```

Notes:
- `entries` is the **post-exclude** set — the files FilmCan actually copied, using the same enumeration + `SourceFilterMatching` the backup used. Files the backup ignores (e.g. `.Spotlight-V100`, excluded patterns) never affect seal state.
- `volumeUUID` sourced from existing `DriveUtilities`/`DriveInfo`. On mismatch at read time → `.none`.

### `CardSealService` (Service)

```
enum SealState {
    case none                         // no marker, or unreadable/foreign/old-schema
    case sealed
    case broken(added: [String], missing: [String], modified: [String])
}

func seal(source: URL, entries: [CardSeal.Entry],
          destinationsVerified: [String], mhlRef: String?) throws
func evaluate(source: URL) -> SealState
```

- `seal(...)` writes the marker. Called **after** a fully-verified run (decision C). Best-effort (see Error handling).
- `evaluate(...)` reads the marker, re-enumerates the current card with the backup filter, structural-diffs `entries` against current state:
  - identical set (relPath + size + mtime all match) → `.sealed`
  - any current file absent from marker → `added`
  - any marker file absent from card → `missing`
  - matching relPath with different size or mtime → `modified`
  - any of added/missing/modified non-empty → `.broken(...)`

### `SealState` → surfaces

- **Badge** (`SourceListView`): map state → icon + label + colour. `.sealed` = green ✓ "Backed up & verified"; `.broken` = orange ⚠ with a short "N files added since backup"; `.none` = neutral/absent.
- **Eject guard**: at the existing `DriveEjector.eject` call site, evaluate the source; if `!= .sealed`, present a confirmation sheet ("This card isn't sealed as backed-up. Eject anyway?") with Cancel / Eject.

## Data flow

1. Backup run completes; every planned destination reports verified for source `S`.
2. `TransferViewModel` (post-run) calls `CardSealService.seal(S, entries: <backed-up set from the run>, destinationsVerified:, mhlRef:)`.
3. `seal` writes `.filmcan-seal.json` at `S` root and updates in-app state → badge flips to ✓.
4. Later, card re-inserted → drive detection → `evaluate(S)` → badge reflects current state.
5. Operator ejects → guard evaluates → confirmation if not `.sealed`.

The backed-up entry set in step 2 is already known to the run — it is **not** re-derived by walking the card again, avoiding a race with any post-run writes.

## Error handling

- **Read-only card / write failure when sealing**: best-effort. Keep an in-memory session seal state so the badge is still correct for this session, surface a non-fatal note ("Couldn't write the seal to the card"). **Never fail or roll back the backup because sealing failed.**
- **Contents changed since seal**: `.broken`, badge shows what changed (counts).
- **Marker malformed / unknown `schemaVersion` / `volumeUUID` mismatch**: treat as `.none`. Never crash, never trust a foreign marker.
- **Marker present, card empty / all files removed**: `.broken(missing: all)`.

## Testing

FilmCan convention: real temp-dir disk I/O, no mocks.

**Unit**
- `CardSeal` encode/decode round-trip; unknown `schemaVersion` decodes to `.none` handling.
- `evaluate` structural diff matrix:
  - identical set → `.sealed`
  - one file added → `.broken(added:[...])`
  - one file removed → `.broken(missing:[...])`
  - one file size changed → `.broken(modified:[...])`
  - one file mtime changed → `.broken(modified:[...])`
  - excluded/ignored file added → still `.sealed` (filter parity with backup)
  - foreign `volumeUUID` → `.none`

**Integration**
- Temp-dir acting as a "card": seal it, `evaluate` unchanged → `.sealed`; mutate (add/remove/modify) → `.broken` with correct lists.
- Seal only written when all destinations verified (decision C): simulate one dest failing → no marker, state `.none`.

## Out of scope (YAGNI)

- Raw block writes / force-reformat / any destructive card mechanism.
- Privileged helper, SMAppService, notarization changes.
- Volume rename as a signal surface (rejected: mutates volume identity, breaks `{sourceDriveName}` tokens and re-detection).
- Deep re-hash on re-insertion (possible future opt-in, not this feature).
- Visible on-card marker file.

## Touch points (existing code)

- `FilmCan/Sources/Models/` — new `CardSeal.swift`.
- `FilmCan/Sources/Services/` — new `CardSealService.swift`.
- `FilmCan/Sources/ViewModels/TransferViewModel.swift` — call `seal(...)` on fully-verified run completion.
- `FilmCan/Sources/Views/SourceListView.swift` — badge.
- `FilmCan/Sources/Utilities/DriveEjector.swift` call site — eject guard confirmation.
- Reuse: `DriveUtilities`/`DriveInfo` (volume UUID), `FileEnumerator` + `SourceFilterMatching` (filter parity), ASC MHL ref for traceability.
