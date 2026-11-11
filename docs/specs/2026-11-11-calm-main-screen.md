# Calmer main screen

**Date:** 2026-11-11 · **Lot:** 4 · **Branch:** `qt1/calm-main-screen`

## Goal

The main screen should answer one question at a glance: what goes where, and is it safe to press Run. Today every element has the same weight, the shoot day is buried in Options, and paths, numbers and a full folder tree are always shown. This lot adds one dominant line and removes chrome that carries no information. The film tabs, the two columns and the flow links between them are untouched.

## Expected behaviour

### 1. Shoot day in the film header

A `‹ Day02 ›` stepper sits next to the film title.

- Shown only when the film's active folder templates (camera or sound) or rename template contain `{day}`. Otherwise it is absent, not greyed.
- The arrows move the trailing number, keeping prefix and width (`Day02` → `Day03`, `D9` → `D10`). Never below 1. An empty day steps forward to `Day01`. A day without a trailing number (`Pickups`) shows both arrows disabled; free text is still typed in Options › Source.
- It shows the day a run started now would use (`effectiveShootDay`).
- Day counter off: an arrow changes the film's day, exactly like the existing field.
- Day counter on: an arrow sets today's value (the existing "today" override); tomorrow's first run advances from it.
- Disabled while that film is copying.

### 2. One summary line

Between the header and the two columns: the destination breadcrumb, then size, file count and drive count.

`CITIZENK › Day02 › A003        128 GB · 412 files · 2 drives`

- The breadcrumb is the engine's own destination path for the included source, relative to the drive (same function as the folder preview), so it cannot disagree with the copy.
- Several sources: the folders they share, then `3 items`.
- No source: no line. No drive yet: the line still names the folders. Sizes still loading: `Measuring…`.

### 3. Run button subtitle

Under "Run Now", one sentence: `Add a card or a folder to copy`, `Add a drive to save to`, `3 folders will be created` (summed over included drives), `Folders already exist: only missing files are copied`, or `Backup in progress`. The button's enabled state and action are unchanged.

### 4. Less chrome

- A source that is a whole drive (`/Volumes/NAME`) no longer repeats its path under its name; the path is the tooltip. A folder inside a drive or on the Mac keeps its path line.
- Order numbers next to the checkboxes appear only when there are several rows.
- The shared folder preview in Save To folds to one line, "Folders already on every drive", when nothing in it is new. One click opens it. With anything new it is open as before.

### 5. History as a list by default

The history pane opens as the compact list. The existing switch still offers the film-can cards. The preference key is unchanged, so anyone who already used the switch keeps their choice.

## What does not change

- Flow links, film tabs, card layout, colours, fonts.
- The Options card (its move into a settings panel belongs to a later lot).
- The engine and everything a run writes. No configuration field is added.
- Quick Copy.

## Edge cases

- Text-only shoot day: stepper shown, arrows disabled, tooltip points to Options.
- A file source next to a card: the breadcrumb treats the last component as the item, never as a shared folder.
- Per-drive trees (drives that differ) are not folded in this lot.

## Success criteria

- Changing the shoot day takes one click from the main screen.
- Unit tests cover the stepper arithmetic (and agreement with the day counter), when the day is shown, the breadcrumb, the subtitle, and the three chrome rules.
- Visual criteria (fewer than 25 text elements for 1 card and 2 drives; 3 sources and 2 drives readable at 1280 × 800) can only be judged on the real app: listed in the PR.
