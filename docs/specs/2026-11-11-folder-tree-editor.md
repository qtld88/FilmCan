# Visual folder layout editor

**Date:** 2026-11-11 · **Lot:** 6 · **Branch:** `qt1/folder-tree-editor`, stacked on `qt1/film-settings-panel`

## Goal

Today the folder layout of a movie is a line of text with names in braces: you must read `{movie}/{day}/Camera` and a list of thirteen names to know where the rushes go. Make the layout a small tree you edit directly, with a mark where cards land and a mark where sound lands. The text stays, as another view of the same setting.

## Expected behaviour

### 1. The tree (Movie settings › Destinations › Folder layout)

- A tree starting at "Drive", one row per folder. A folder named automatically shows the name in clear ("Movie name", "Shoot day", "Date", "Project / episode", "Unit", "Camera format"); a folder with a mixed name shows it with the automatic parts marked (`‹Date›_‹Shoot day›`).
- Two marks: "Cards go here" on the folder that receives the cards' folders, "Sound goes here" on the one that receives sound. They can be the same folder.
- Each row has a menu: Rename (plain names only), Add a folder inside (a named folder, or one of the automatic names), Move up, Move down, Remove. "Drive" has an add button. Under the tree: "Give sound its own folder" / "Put sound with the cards".
- Above the tree, four starting points: One day (Movie › Camera, Sound), Several days (Movie › Shoot day › Camera, Sound), Netflix Ingest (the Netflix layout), Free (empty). Replacing an existing layout asks first.
- No drag and drop in this lot. No "create the folders now" button: folders are created by the first backup, as today.

### 2. Same setting as the text

The tree reads and writes the two strings the engine already uses (camera layout and sound layout). For the Netflix preset these are the movie's two editable fields; otherwise the layout of the movie's own settings. A movie that had no settings of its own gets them on its first edit in the tree (needed to hold a separate sound folder).

**Lossless or read-only.** The tree shows a layout only if it can write it back character for character. Otherwise (a name it does not know such as `{source}`, `{counter}` or a file date; an empty folder name; a backslash; spaces around the text; a sound layout without a camera layout; identical camera and sound layouts; a folder name a run would write differently, such as an accented letter, `&`, doubled underscores, `.` or `..`) it steps aside: one sentence, and the text field below remains the editor. Nothing is rewritten on display: a layout changes only when the user edits it.

**Never over something kept.** The tree is not offered, with one sentence saying why, when an edit would replace something the movie keeps: a layout that is switched off but still has its text (switch it on first), and a movie on "Off" whose own settings are set aside (choose them again in the Preset menu first). A name typed in the tree is cleaned to what a run writes.

Three things the text cannot say, so the tree does not offer them: sound at the top of the drive while cards are in a folder, sound in a folder while cards are at the top, and an empty layout that is switched on (emptying the tree switches the layout off).

### 3. "new" marks in the folder preview

In the folder preview (Save To and Quick Copy), a folder that does not exist yet carries a small "new" mark next to its name, in addition to its colour. Files and "contents of…" lines do not.

## What does not change

- The resolver, the engine, what a run writes. No stored field added.
- Any existing layout, until its owner edits it.
- The text field and its list of names.

## Success criteria

- The three reference structures and the Netflix one are produced without typing a name in braces: One day and Several days from the row menus, Netflix from its starting point (test).
- Round trip: every shipped layout and every starting point goes text → tree → text unchanged; layouts the tree cannot show are declared not editable (test).
- A structure built in the tree resolves, through the engine's own function, to the folders the tree shows (test).
- The preview marks folders to be created (test on the rule; look on the real app).

## Not in this lot

- Empty sibling folders (exports, reports…) created with the layout: it needs a new stored field and a step in the engine.
- Drag and drop.
- The roll-name composer (prefix, number width) inside the tree: it stays in Source › Cards & rolls.
- The rename template in the tree.
