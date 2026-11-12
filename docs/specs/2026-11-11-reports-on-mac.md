# A copy of every report on the Mac

**Date:** 2026-11-11 · **Lot:** 3 · **Branch:** `qt1/reports-on-mac`

## Goal

A backup report lives on the destination drive. Once the drive leaves, the proof of the backup leaves with it. Keep a copy of each report on the Mac, readable with every drive unplugged.

## Expected behaviour

After a backup that writes a PDF report (the film's existing "PDF report with thumbnails" switch), FilmCan copies, for each destination:

- the PDF,
- the checksum list of each roll written by that run: the latest ASC MHL generation in the roll's `ascmhl/` folder, or the simple hidden list (`.filmcan/hashlists/<roll>.mhl`) when the film uses that style,

into `<base>/<film>/<day>/<drive>/`.

- `<base>`: `~/Documents/FilmCan Reports` by default, changeable.
- `<film>`: the film's name.
- `<day>`: the film's shoot day when set, else the run's calendar date (`2026-11-11`).
- `<drive>`: the destination's volume name (the folder name when the volume is unknown). One folder per drive, because two drives can produce the same file names.
- Names are made safe: `/` and `:` become `-`, leading dots are removed, an empty name gets a fallback. A name can never leave the base folder.
- ASC MHL file names already carry the roll; a list that does not is prefixed with it.

Settings › History gains a "Reports" section: a switch "Keep a copy of every report on this Mac" (on by default), the folder path, "Choose…", "Reset" (only when a custom folder is set), "Show in Finder". Preferences: `reportArchiveEnabled` (absent = on), `reportArchiveFolder` (absent or blank = default).

No network access. If the chosen folder is synced by another tool, that tool syncs.

## Decision to note: when the copy is made

The copy is tied to the report: no PDF report, no copy. A film that has the report switched off therefore gets nothing new anywhere, which keeps existing films exactly as they were. The alternative (copy the checksum lists even without a PDF) would start writing into Documents for every existing film; rejected as a surprise. Changing this later is one condition in `TransferViewModel`.

## Edge cases

- Copy fails (folder not writable, Documents access refused, disk full): logged, skipped. The backup result, the history and the report on the drive are unaffected. Each file is copied to a hidden temp name then moved, so a failed copy leaves no half file.
- Same film, same day, same drive, second run: new log name, so a new PDF; a same-named checksum list is replaced by the newer one.
- Resumed run where a roll was entirely skipped: that roll is not in the run's result, so its list is not re-copied (it was copied by the run that wrote it).
- Quick Copy: its temporary film has the report off, so no copy.

## What does not change

- Nothing on the destination drives: same folders, same files (a test compares the drive before and after).
- The report writer, the engine, verification, manifests, history format, configuration format.

## Success criteria

- Unit tests: default and custom folder, layout, safe names, latest-generation pick, copy and replace, switched off, quiet failure, drive untouched.
- Manual: the PDF opens from the Mac with the drives ejected.
