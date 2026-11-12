# Recognition page

**Date:** 2026-11-11 · **Lot:** 7a · **Branch:** `qt1/recognition-page`, stacked on `qt1/film-settings-panel`, with `qt1/more-cameras` merged in

## Goal

FilmCan already recognises cards and remembers corrections, but nothing says how it decides or what it has kept. Add one page to the Settings window that explains it in plain sentences and lists what is remembered, with a way to forget an entry.

## Expected behaviour

Settings › **Recognition** (sidebar, after Drives), four groups:

1. **How FilmCan recognises a card** — one sentence per thing it looks at (folder and file names, external drives only, three levels deep, WAV without video = sound recorder, a recognised card is only proposed, corrections are remembered, backup drives are not guessed). One line says where detection is switched on (Movie settings › Source).
2. **Cards it knows** — one line per family, built from the detector's own list (`CameraBrand.allCases`: name + `recognisedBy`). A family added to the detector appears with no other change.
3. **Your corrections** — every drive whose role was set by hand (right-click in Copy From): drive name, role, date, "not connected" when it is not mounted. **Forget** removes the correction; FilmCan guesses again for that drive.
4. **Roll names it remembers** — per movie (movies in their usual order, then movies that no longer exist as "Deleted movie"): each card's roll name, with the drive's name when it is connected. The movie line shows the number of cards and the date of its last backup. **Forget** removes one card's roll name; the card gets the next free name the next time it is used with that movie.

The page reads; it has no switch. Detection itself is unchanged.

## Edge cases

- **Corrections made before this version** have no stored name or date: listed as "Drive not connected (first 8 characters of its id)" until the drive is mounted, then by its current name.
- A stored role this version does not know is ignored (not listed, not applied — as today).
- A card stored without a volume id (`nouuid|…`): listed by roll name and folder only.
- Forgetting a roll name never frees that name: it stays taken for the movie (kept in `roll-numbering.json` under a key that is not a card), because a roll folder of that name may be on a drive. The forgotten card gets the next free name and is copied again in full under it. "Reset numbering" clears the names kept aside too.
- Forget does nothing if the card's roll name changed since the page was drawn.
- Forgetting a correction does not change movies: a card already listed in a movie, or tagged Sound there, stays as it is.
- The lists refresh when the page appears and when the app becomes active (a drive plugged meanwhile).

## What does not change

- `CameraCardDetector`, `FilmDriveDetector`, the copy engine, verification, manifests.
- The stored corrections (`filmcan.cardRoleOverrides`, same key, same format) and `roll-numbering.json` (same format).
- Any movie's settings. Detection stays per movie; name rules stay where they are.

## Stored data added

One preferences entry, `filmcan.cardRoleOverrideDetails`: for each correction, the drive's name and the date. Written when a correction is made, removed with it. Only this page reads it; absent for older corrections (tested).

## Success criteria

- A test fails if a family of the detector's enum is missing from the page or lacks a name or a sentence.
- A correction saved by an earlier version still applies and is listed (test).
- Forget removes exactly one entry and is saved (tests on both stores).
- A wrong proposal stays correctable in two clicks (right-click, choose) and the correction is visible on the page.

## Not in this lot

- Guessing backup drives, showing a reason or confidence on each card (later lot).
- A per-card "last used" date: only the correction date and the movie's last backup date are known today.
- Moving the per-movie detection switch or the name rules.
