# Movies only, no presets

**Date:** 2026-11-15 · **Lot:** 10 · **Branch:** `qt1/films-only`

## Goal

A movie is the only kind of settings. Presets go away: no Preset menu, no "Save as new preset", no "Delete preset", no "different from the preset" warning. To reuse settings, create a new movie from an old one, from the built-in Netflix Ingest model, or from a movie settings file. Quick Copy picks a movie and no longer a preset.

The code already went half way: every movie owns a private copy of its settings (`FilmPresetOwnership`, `ownerFilmId`), and shared presets are only a starting point, never a live link. This lot removes the second idea, which no longer adds anything.

## Decisions (validated 2026-11-15)

1. **Netflix Ingest stays, as a model** to start a movie from (and to apply to a movie, see below). It is built into the app, never stored.
2. **Shared presets are dropped.** Beta: the shared presets no movie uses are deleted on the first launch, without conversion.
3. **A movie made from another copies settings only.** Never the shoot: roll numbering, day, episode, history, catalog, sealed cards, card names, drives.
4. **Quick Copy keeps "No movie"** (basic options). A change made in Quick Copy is for that copy only and never written to the movie.
5. **Export and import of one movie's settings** replace the preset export.

## What the user sees

**New movie.** The "+" button (and File › New Backup, ⌘N) no longer creates a movie at once: it asks what to start from. The separate chevron menu goes away. A small popover (or sheet, when opened from the menu) lists, in this order:

- **Blank movie**: today's first-run defaults (`BackupConfiguration.newFilm(name:)`).
- **Netflix Ingest**: a blank movie with the Netflix Ingest folder settings (same values as today's built-in preset, `Reports` log folder included).
- **Like ‹movie›**, newest first: today's `BackupConfiguration.newFilm(name:like:)`.
- **From a settings file…**: opens a `.filmcan-movie` file (see Export).

Picking one creates the movie and selects it; closing the popover creates nothing. With no movie yet (first launch, "Create First Movie"), the same choice shows, without the "Like" list. File › New Movie Like goes away (the choice covers it). "Start from a preset" disappears.

**Movie settings, Destinations › folder section.** The Preset menu (checklist S4) is replaced by:

- the existing on/off switch for folder organization (today's "Off"),
- a **Use Netflix Ingest folders** button: after a confirmation ("Replaces this movie's folder and naming settings"), puts the Netflix Ingest values into the movie's own settings. Same result as picking Netflix Ingest in today's menu.

The "Preset changed" / "differs from preset" lines and their reset buttons go away: there is nothing left to differ from.

**Quick Copy.** The Preset row and the "Save as preset" panel go away. The Movie picker stays, with **No movie** first:

- *No movie*: basic options, as today without a preset.
- *A movie*: its folder settings, project and day are loaded, plus its mounted sources and destinations (unchanged from today). The chips show the movie's settings. The per-copy overrides (duplicates, folder vs contents, Camera/Sound folder) stay overrides for this copy.

**Settings › Import & Export.** The "Presets" row goes away. "Movies & History" stays as it is. An old presets file opened anywhere shows: "Presets no longer exist. Create a movie and export its settings instead."

**Export one movie's settings.** In the movie's right-click menu and in the movie settings panel: **Export Settings…** saves `‹Movie name›.filmcan-movie`. Import is "New movie › From a settings file…", which always creates a new movie and never overwrites one.

## Data

**The movie's own settings record stays.** The engine reads a movie's folder and naming settings from its own `OrganizationPreset` record (`ownerFilmId == movie id`, pointed at by `selectedOrganizationPresetId`). This lot keeps that record and the engine path untouched (`TransferViewModel.resolveOrganizationPreset`, `OrganizationTemplate.resolve`, `FanOutCopier`). Only the shared records and their UI go. Renaming the type is out of scope: it would touch the engine for no user gain.

**Migration, once, at load (`ConfigurationStorage`):**

1. Run `FilmPresetOwnership.adopt` (already idempotent), so every movie pointing at a shared preset has its own copy first.
2. Delete every record with `ownerFilmId == nil`.
3. Delete own copies whose movie no longer exists (orphans).

A movie whose `selectedOrganizationPresetId` matches nothing is left alone, as today. Running it again changes nothing. The migration writes nothing else.

**Settings file `.filmcan-movie`.** JSON, versioned:

```json
{ "format": "filmcan-movie", "version": 1,
  "movie": { …BackupConfiguration… },
  "folderSettings": { …OrganizationPreset or null… } }
```

- **Export** writes the movie as `newFilm(name:like:)` would leave it: no drives, sources, destinations, card names, day, run roll names. The id is not written.
- **Import** decodes, gives a new id and the file's name (renamed "‹name› 2" when taken), and gives the movie its own copy of `folderSettings` (`ownerFilmId` = new id). The `{movie}` leading folder rule (`FilmTemplate.replacingLeadingFilmFolder`) already ran at export.
- An unknown `version` or `format` is refused with a plain message. Unknown fields are ignored (Codable defaults), so a newer FilmCan's file opens when it can.

**What "new movie like" resets.** Today's `newFilm(name:like:)` already resets drives, sources, destinations, kinds, card names, run roll names, day, usage dates. It also must reset **episode** (shoot-specific). Unit and camera format are kept (crew setup). Roll counters, history, catalog and seals are keyed by movie id, so a new id starts them fresh. A test checks each of these.

## Same folders and files

An existing movie must produce the same folders and files after the update. That holds because:

- its own settings record is kept, unchanged and still pointed at;
- movies on a shared preset get their own copy (step 1) before the shared ones are deleted (step 2);
- the engine is untouched.

**Test:** for a stored set of movies (one with no preset, one on its own copy, one still pointing at a shared preset, one on Netflix Ingest with edited templates), resolve the destination folder tree before and after the migration and compare. They must be equal.

## Code removed

- `PresetDivergence.swift` and its call sites (overview line, reset buttons).
- In `BackupEditorViewModel`: shared-preset list, select/save/delete preset, `replaceOwnCopy(with:)` from a shared preset (kept only for "Use Netflix Ingest folders").
- In `QuickCopyFormModel`: `selectedPresetId`, `pickerPresets`, `savePresetName`, `presetDiffersFromFilm`, save-as-preset. The run preset comes from the selected movie's own record or none.
- `AppState.presetsToStartFrom`, `createNewConfig(fromPreset:)`.
- `ConfigurationStorage.exportPresetsData` / `importPresets`, Settings "Presets" row.
- `OrganizationPreset.projectName` / `hashListStyle` stay (read from the movie's record by Quick Copy).

## Tests (logic only)

- Migration: adopt-then-delete keeps every movie's resolved tree (above); a second run changes nothing; orphans removed; a shared preset no movie uses is gone.
- New movie like: every reset field listed above, and the kept ones.
- Netflix Ingest model: a new movie from it resolves the same tree as today's built-in preset.
- Settings file: export → import round trip gives equal settings with a new id, no drives, no day/episode; unknown version refused; old presets file refused with the message; name clash gets " 2".
- Quick Copy: with a movie, the configuration uses that movie's own record; with No movie, none; switching movie does not write the movie.

## Checklist

`ESSAI-CHECKLIST.md` / `docs/smoke-qa-checklist.md`: S4 replaced by:

- **S4** No Preset menu anywhere; Destinations has the organization switch and "Use Netflix Ingest folders".
- **S4b** "+" asks: Blank movie, Netflix Ingest, Like ‹movie›, From a settings file…; closing it creates nothing.
- **S4c** Export Settings → import as new movie: same folders on a test copy, no drives, day or episode carried over.
- **S4d** After updating with your current settings: each movie copies to the same folders as before.
- Quick Copy gate (Q rows): Preset row and Save as preset gone; Movie picker with No movie.

Docs: `docs/features/destination-presets.md` rewritten as "Starting a movie from another", `quick-copy.md` and `netflix-ingest.md` updated.

## Out of scope

- Renaming `OrganizationPreset` in code.
- Live links between movies (a "house standard" edited once for all movies). It does not exist today either.
- Importing a settings file into an existing movie.

## Effort

About 1.5 to 2 days: migration and tests ½ day, New movie menu + settings file ½ day, editor and Quick Copy UI ½ day, removals, docs and checklist ½ day.
