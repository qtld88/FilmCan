# Movie settings panel, Settings sidebar, plain labels

**Date:** 2026-11-11 · **Lot:** 5 (part 2 of 2) · **Branch:** `qt1/film-settings-panel`, stacked on `qt1/film-settings`

## Goal

Every setting has one home, and its scope shows where it lives: app-wide settings in the Settings window, a movie's settings in a panel next to that movie. The main screen keeps one quiet line for them instead of a card with a tab bar. First-level labels say the effect in plain words.

## Expected behaviour

### 1. Movie settings panel

- The Options card under the main screen is replaced by one line: a gear, "Movie settings", and a summary (`Netflix Ingest · Full check (re-reads every file)`).
- Clicking the line opens the movie's settings as a panel on the right of the editor, inside the main window. Copy From and Save To stay visible on the left; the folder preview follows every change. Clicking the line again, or the panel's close button, closes it.
- The panel holds the same four groups as before (Basic, Source, Destinations, Logs) and the Preset menu, laid out in their existing narrow form. Nothing is removed or moved between groups.
- One side pane at a time: opening the panel closes History / Catalog; opening History or Catalog closes the panel.
- The panel's open state is one app preference: it stays open when switching movies and across launches.
- Choosing a preset from the menu opens the panel if it was closed (as it used to expand the card).
- The quick tour step that pointed at the tab bar now points at the line.

### 2. Settings window

The seven tabs across the top become a sidebar with the same seven pages, in the same order, with the same content. Two are renamed: "Push" → "Phone & webhooks", "Hotkeys" → "Shortcuts". The window is wider (740 pt) to make room for the sidebar. The last page opened is remembered.

### 3. Plain labels

| Before | After |
|---|---|
| Paranoid (verification choice) | Full check (re-reads every file) |
| Fast (verification choice) | Fast check |
| Duplicate policy | If a file already exists |
| Hash list style | Checksum list format |
| Folder template(s) | Folder layout |
| File Rename Template / File name template | Rename files |
| Custom date for tokens | Custom date in names |

Only what is shown changes. Stored values, log lines, history entries and notification text keep their current words.

## What does not change

- Any stored setting, any file format, what a run writes.
- The content of each options group and each Settings page.
- Quick Copy.

## Edge cases

- Window too narrow for both: the panel takes at most half the editor (340 to 460 pt) and the cards stack, as they already do in a narrow window.
- A movie switched while the panel is open: the panel shows the new movie's settings.
- The phone/webhook form still names its technical fields (address, access key): it is reorganised by the phone-notifications lot, not here.

## Success criteria

- Tests: no first-level label contains paranoid, bearer, token, hash, policy or template; each verification choice has its own label; the seven Settings pages are all present; an unknown stored page opens the first one; the one-pane rule; panel width bounds.
- Visual criteria (panel fits, cards stay readable, sidebar looks right) are judged on the real app: listed in the PR.

## Not in this lot

- An "Advanced" fold inside each group (which rows count as advanced is a call to make on the real screen).
- A help sentence under each group.
- Moving a setting from one group to another.
