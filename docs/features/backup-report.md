<!-- lang:en -->
# PDF Backup Report

FilmCan can write a readable PDF for each destination after a backup, next to the transfer log.

---

## What is in it

- Header: project, episode/day/unit (when set), destination volume and path, start/end time, duration, status (Verified, Copied not verified, Failed), warning, FilmCan version.
- Summary: one line per roll with kind (Camera/Sound), file count and total size.
- One section per roll: a row per file with a thumbnail, name, relative path, size, duration (video/audio) and checksum.

The report lists everything on the drive in the roll folder, including files skipped on a resumed run. XML sidecars and other non-media files are listed with their file icon.

## Enable it

Options › Logs › **PDF report with thumbnails**. It needs **Create log file** to be on; the toggle is greyed out otherwise.

## Where it goes

`<log file name>_report.pdf`, in the same folder as the log. With the Netflix Ingest preset the log goes in the shoot-day `Reports/` folder, so the PDF does too.

From History, right-click a card and choose **Open report** when the PDF exists.

## Good to know

- Generated in the background after history and notifications; it never delays or fails the backup.
- Checksums come from the roll's latest ASC MHL manifest. With the simple hidden hash list style, checksums are left blank.
- Thumbnails come from macOS QuickLook. ARRI, RED and BRAW clips show a file icon unless a QuickLook plugin is installed.
- Large cards (hundreds of clips) can take a few minutes.
