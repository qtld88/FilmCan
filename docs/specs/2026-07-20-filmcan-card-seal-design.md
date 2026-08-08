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
| A | Marker location | **Hidden** `<source>/.filmcan/seal.json` | Camera-safe; inside the existing `.filmcan` namespace already excluded by `FileEnumerator`, so it never self-references. Human visibility comes from the in-app badge + eject guard, not from a file on the card. |
| B | Eject guard hardness | **Warn + confirmation** (soft, overridable) | A hard block is hostile on set; explicit confirm preserves operator control while catching mistakes. |
| C | Multi-destination rule | Seal **only if every planned destination verified** that card's files | The seal means "safe to wipe." A partial fan-out is not safe. |
| D | Re-insertion check | **Structural** (relPath + size), no mtime, no re-hash | The real hash verification already happened during backup. Re-hashing on every insertion is too slow (future opt-in, out of scope). mtime dropped: exFAT 2s granularity causes false `.broken`, and `SourceFileEntry` has no mtime. |

## Components

### `CardSeal` (Model, Codable)

Serialized to `<source>/.filmcan/seal.json` — inside the existing `.filmcan` hidden namespace (`FilmCanPaths.hidden`), which `FileEnumerator` already excludes. This means the marker file itself is never counted as a card file, so it can never make a card read `.broken` against itself.

```
struct CardSeal: Codable {
    let schemaVersion: Int          // bump on format change; unknown → treated as .none
    let volumeUUID: String          // identity guard against a marker copied to another card
    let sealDate: Date
    let appVersion: String
    let entries: [Entry]            // exactly the set actually backed up (post-exclude)
    // Filter patterns used at backup time — stored so evaluate() reconstructs an
    // identical FileEnumerator filter without needing the live preset.
    let includePatterns: [String]
    let excludePatterns: [String]
    let copyOnlyPatterns: [String]
    let destinationsVerified: [String]
    let mhlRef: String?             // path/name of the sealing ASC MHL manifest, for traceability

    struct Entry: Codable {
        let relPath: String
        let size: Int64
    }
}
```

Notes:
- `entries` is the **post-exclude** set, obtained by calling `FileEnumerator.enumerateFiles(sources:preset:)` and mapping each entry to `relPath`+`size`. `FileEnumerator` already emits only regular files (directories are skipped internally); its `sourceIsDirectory` flag describes the source *root*, not the entry, so it must not be used as a per-entry filter. Enumeration parity between seal time and evaluate time is guaranteed because the marker stores the three filter-pattern arrays and `evaluate` rebuilds a throwaway `OrganizationPreset` from them. This is why `SourceListView` (which has no preset) can still evaluate correctly.
- `volumeUUID` sourced from `url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString` (same key `DriveUtilities.summary` reads). On mismatch at read time → `.none`.
- **No `mtime`.** Refinement from the approved design: `SourceFileEntry` carries no mtime, and exFAT's 2-second mtime granularity produces false `.broken`. `relPath` + `size` is sufficient for camera cards (append-only footage, new clips = new filenames).
- **`size` is the logical byte size**, re-read via `.fileSizeKey` in `CardSealService.enumerate` — *not* `SourceFileEntry.size`, which is the allocated (block-rounded) size and would hide sub-block resizes.

### `CardSealService` (Service)

```
enum SealState: Equatable {
    case none                         // no marker, or unreadable/foreign/old-schema
    case sealed
    case broken(added: [String], missing: [String], modified: [String])
}

func seal(source: URL, preset: OrganizationPreset?,
          destinationsVerified: [String], mhlRef: String?) async throws
func evaluate(source: URL) async -> SealState
```

- `seal(...)` enumerates the source (via `FileEnumerator` with `preset`, files only, `relPath`+`size`), captures `preset`'s three pattern arrays, writes the marker. Called **after** a fully-verified run (decision C). Best-effort (see Error handling).
- `evaluate(source:)` reads the marker, rebuilds a throwaway `OrganizationPreset` from the marker's stored pattern arrays, re-enumerates the current card with that same `FileEnumerator` filter, structural-diffs `entries` against current state:
  - identical set (every `relPath` present with matching `size`) → `.sealed`
  - any current file absent from marker → `added`
  - any marker file absent from card → `missing`
  - matching `relPath` with different `size` → `modified`
  - any of added/missing/modified non-empty → `.broken(...)`

`evaluate` needs no external preset — the marker is self-contained.

### `SealState` → surfaces

- **Badge** (`SourceListView.sourceRow`): map state → icon + label + colour. `.sealed` = green ✓ "Backed up & verified"; `.broken` = orange ⚠ "N files changed since backup"; `.none` = neutral/absent. Rendered by a small `CardSealBadge` subview holding `@State var state` populated in a `.task { await CardSealService.evaluate(source:) }` (no preset needed).
- **Eject guard** (`SourceListView.ejectVolume(for:onSuccess:)`, the source-side eject at line ~492): before calling `DriveEjector.eject`, evaluate the source; if `!= .sealed`, present a confirmation alert ("This card isn't sealed as backed-up. Eject anyway?") with Cancel / Eject. (Destination-side eject in `DestinationListView` is out of scope — the seal is about source cards.)

## Data flow

1. Backup run completes; `TransferViewModel` holds `perDestResults: [TransferResult]`.
2. **Seal gate (decision C):** source `S` is sealed iff, for every planned destination `d`, there is a per-dest `TransferResult` with `success == true && wasVerified == true`. This covers both fresh verified copies and an already-present-and-verified re-run.
3. If the gate passes, `TransferViewModel` calls `CardSealService.seal(source: S, preset:, destinationsVerified:, mhlRef:)` for each source `S`. `seal` enumerates `S` and writes `<S>/.filmcan/seal.json`.
4. Later, card re-inserted → source row renders → `evaluate(S)` → badge reflects current state.
5. Operator ejects a source → guard evaluates → confirmation if not `.sealed`.

The backed-up entry set in step 2 is already known to the run — it is **not** re-derived by walking the card again, avoiding a race with any post-run writes.

## Error handling

- **Read-only card / write failure when sealing**: best-effort. Keep an in-memory session seal state so the badge is still correct for this session, surface a non-fatal note ("Couldn't write the seal to the card"). **Never fail or roll back the backup because sealing failed.**
- **Contents changed since seal**: `.broken`, badge shows what changed (counts).
- **Marker malformed / unknown `schemaVersion` / `volumeUUID` mismatch**: treat as `.none`. Never crash, never trust a foreign marker.
- **Marker present, card empty / all files removed**: `.broken(missing: all)`.

## Testing

FilmCan convention: real temp-dir disk I/O, no mocks.

**Unit**
- `CardSeal` encode/decode round-trip; a marker with an unknown `schemaVersion` → `evaluate` returns `.none`.
- `evaluate` structural diff matrix:
  - identical set → `.sealed`
  - one file added → `.broken(added:[...])`
  - one file removed → `.broken(missing:[...])`
  - one file size changed → `.broken(modified:[...])`
  - excluded/ignored file added (e.g. inside `.filmcan/` or `.Spotlight-V100`) → still `.sealed` (filter parity)
  - foreign `volumeUUID` → `.none`
  - no marker → `.none`

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

- `FilmCan/Sources/Models/CardSeal.swift` — new.
- `FilmCan/Sources/Services/CardSealService.swift` — new.
- `FilmCan/Sources/ViewModels/TransferViewModel.swift:~193` — after the `for group` loop, seal-gate on `perDestResults` + call `seal(...)` per source.
- `FilmCan/Sources/Views/SourceListView.swift:~229` (`sourceRow`) — badge; `:~492` (`ejectVolume`) — eject guard.
- Reuse: `FileEnumerator.enumerateFiles(sources:preset:)` (filter parity), `.volumeUUIDStringKey`, `FilmCanPaths.hidden`.
