# First-launch defaults

**Date:** 2026-11-11 · **Lot:** 0 · **Branch:** `qt1/first-launch-defaults`

## Goal

Make the first minutes of a new user smoother with three small changes that do not touch the copy engine.

1. macOS file-access dialogs explain why FilmCan asks.
2. A film the user creates recognises camera and sound cards without any setup.
3. A film the user creates writes a PDF report after each backup.

## Expected behaviour

### 1. File-access dialog text

`FilmCan/Sources/Info.plist` gains five usage descriptions: removable volumes, network volumes, Documents, Desktop, Downloads. Each is one plain sentence naming FilmCan and saying what it does with the files. `project.yml` points at this hand-written plist (`INFOPLIST_FILE`), so XcodeGen does not regenerate it.

### 2 and 3. New-film defaults

`BackupConfiguration.newFilm(name:)` is the single place that builds a film created by the user. It returns the plain default configuration with `cardAutoDetectEnabled = true` and `reportEnabled = true`. `AppState.createNewConfig()` (the three "new movie" entry points: tab bar "+", list button, first launch) calls it.

## What does not change

- Property defaults and decoding defaults stay `false`. A film saved earlier, with or without the keys in `configs.json`, decodes exactly as before.
- `BackupConfiguration()` / `.empty` are unchanged, so Quick Copy's temporary configuration and "recall settings from history" behave as before.
- No change to the engine, verification, manifests, log location, or the report writer.
- The two toggles stay where they are (Options › Source and Options › Logs) and can be switched off per film.

## Edge cases

- **Log switched off on a new film.** The report toggle is already greyed out without a log, and the run only writes a report when a log path exists. Unchanged.
- **Card detection on a film with no sources.** A recognised mounted card is added to Copy From as soon as the film opens. Destinations are never added; a drive marked "not a card" is skipped. This is the existing behaviour of the toggle.
- **Report time.** Thumbnails are extracted after the copy and verification finish. The added time on a real card was not measured here; it is listed for the owner in the PR.

## Success criteria

- A unit test fails if any of the five usage descriptions is missing from the built app.
- A unit test proves `newFilm` differs from the plain configuration by these two fields only.
- A unit test proves a legacy JSON film decodes with both switches off.
- The full suite is green on the macOS runner.
