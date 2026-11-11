# Create a report after the fact

**Date:** 2026-11-11 · **Lot:** 7b · **Branch:** `qt1/recreate-report`, stacked on `qt1/reports-on-mac`

## Goal

A roll can end up without a PDF report: the report was off during the backup, the file was lost, or another workstation made the copy. Let the user create the report later, from the roll as it sits on a connected drive, without ever claiming more than is known.

## Expected behaviour

- **Where:** Catalog, right-click a roll. For each connected drive that holds the roll: **Create report from ‹drive›** and **Create report from ‹drive›, re-reading every file (slow)**. No connected drive: one greyed entry saying to connect one. One report at a time; a line at the top of the Catalog says which is being created.
- **Finding the roll:** by the drive's id, not its name, so a drive mounted under another name is found. A copy without a drive id (network share) is used when its path exists.
- **Content:** the files on the drive now (hidden files and the `ascmhl` folder left out), thumbnails extracted from them, sizes, durations.
- **Checksums are read, not recomputed.** They come from the checksum list on the drive: every ASC MHL generation in the roll's `ascmhl` folder (a later one wins), else the simple hidden list. A file shows its checksum only if it is in the list and its size still matches. Otherwise it shows why: "Not in the checksum list" or "Size changed since the backup". Files in the list but no longer on the drive are listed as missing.
- **Says what it is:** under the title, the backup date and "Report created after the backup, on ‹date›, from what is on the drive." The status line never says "Verified": it says the checksums come from the backup's list and the files were not re-read, plus any problem counts (red when there are any).
- **Re-reading (explicit, slow):** every listed file of unchanged size is read again and compared. A match keeps its checksum; a mismatch or unreadable file shows "Does not match the checksum list". Status: "Re-checked: N files match the checksum list" or the problem counts.
- **Output:** `‹reports folder on the Mac›/‹movie›/‹day›/‹drive›/‹roll›_report_recreated.pdf`, replaced if it exists, then shown in Finder. Nothing is written on the drive.

## Edge cases

- **No checksum list** (other tool, list deleted): report without checksums, status "No checksum list on this drive: files listed without checksums". Re-reading is skipped (nothing to compare to).
- **Same roll on several connected drives:** one entry per drive, one report per drive (the drive is part of the path).
- **Roll folder gone from the drive, or the reports folder not writable:** an alert; nothing is written.
- **Same size, changed content:** only the re-reading option can see it; the plain report says the files were not re-read.

## What does not change

- The report a backup writes: same content, same wording, same place (test). `BackupReport` gains optional fields that default to "not set".
- The copy engine, verification, manifests: read only.
- The catalog's stored format.

## Decisions

- The PDF goes to the reports folder on the Mac even when the automatic copies are switched off there: the user asked for this file explicitly. Alternative: next to the roll on the drive (writes on a drive that may be a delivery).
- Re-reading compares against the list on the drive with the same checksum function the backup uses; it does not need the source card.

## Success criteria

- No checksum for a file absent from the list or of changed size; no "Verified" anywhere in such a report (tests).
- The report states it was created after the fact, with the date (test on the PDF text).
- A drive mounted under another name is found; another drive with the same name is not mistaken for it (test).
- Nothing is written on the drive (test).

## Not in this lot

- The same entry in History (the Catalog knows the drive and the roll folder; History entries of old runs do not always).
- Episode and unit on the report (the catalog does not keep them).
- Recording the result of a re-read in the catalog.
