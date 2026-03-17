# QA Checklist

Manual test procedure for FilmCan. This validates core flows, both copy engines, and checks for doc/UI mismatches.

---

## Test Setup

1. Create a source folder with a small text file, a medium file (10–100 MB), and a large file (1–5 GB if possible).
2. Create two destination folders on different drives, or two folders on the same drive if only one drive is available.
3. Ensure you can read the source and write to both destinations.

---

## Core Flow — rsync Engine

1. Set **Copy engine** to `rsync` in **Options > Basic**.
2. Open **Transfer refinements** and turn **Verify after copy** OFF.
3. Click **Run Now**. Expected: transfer completes; destination status shows success (green) with no error message.
4. Turn **Verify after copy** ON and run again. Expected: verification phase runs (blue bar advances); no error message.
5. Open **Transfer History** (clock icon). Expected: history entry created with correct date/time.
6. Right‑click a history card and run **Check data** for a destination. Expected: verification report matches the run.

---

## Core Flow — FilmCan Engine

1. Set **Copy engine** to `FilmCan Engine`.
2. Ensure **Hash verification** is ON in **Options > Basic**.
3. Click **Run Now**. Expected: copy and verification run; blue verification bar advances; destination shows success.
4. Open **Transfer History** and run **Check data**. Expected: verification report matches the run.

---

## Duplicate Handling

1. Run the same backup again with the same sources/destinations.
2. Set **Duplicate policy** to **Skip** and run. Expected: existing files remain unchanged.
3. Set **Duplicate policy** to **Overwrite** and run. Expected: timestamps update and file contents are replaced.
4. Set **Duplicate policy** to **Add counter** and run. Expected: new file names are created with a counter suffix.
5. Set **Duplicate policy** to **Verify using hash list** and run. Expected: identical files are skipped when a hash list exists; mismatches are overwritten. (Ensure verification is enabled so a hash list exists.)
6. Set **Duplicate policy** to **Ask each time** and run. Expected: a duplicate prompt appears for each conflict.

---

## Stop / Cancel / Resume

1. With `rsync`, enable **Only copy new or changed files** and **Allow resume after stop**.
2. Start a transfer with a large file.
3. Click **Stop Backup** (or **Stop Backups**) during copy. Expected: transfer stops; status shows **Cancelled by user**.
4. Click **Run Now** again. Expected: completed files are skipped; the in‑progress file resumes if partials exist.
5. Switch to `FilmCan Engine`, start a transfer, then stop it. Expected: re‑running restarts the in‑progress file (no resume).

---

## Drive Disconnect (Edge Case)

1. Disconnect one destination during copy.
2. Expected: transfer fails with a clear error message for that destination.
3. Reconnect the drive and re‑run.

---

## Permissions (Edge Case)

1. Choose a destination you cannot write to.
2. Expected: pre‑flight validation fails with a readable error.

---

## Logs + Hash Lists

1. Enable **Create log file** in **Options > Logs**.
2. Run a backup.
3. Verify a log file exists at the configured location.
4. Verify a hash list exists at `<destination>/.filmcan/hashlists/` (only if verification is enabled for the engine used).
5. If a log or hash list cannot be created, expected: a warning message appears on the destination card.

---

## Organization Presets

1. Create a preset and enable **Folder template** and **File name template**.
2. Use tokens like `{date}`, `{source}`, `{filename}`, `{counter}`.
3. Run a backup. Expected: folders and filenames match the templates.

---

## Documentation Sanity Check

1. Skim docs for references to UI labels that don’t exist.
2. Confirm tokens listed in docs match the token chips in the app.
3. Confirm options listed in docs match the **Options** tabs in the UI.

---

## Result

Record any failures with:
1. macOS version
2. FilmCan version
3. Steps to reproduce
4. Expected vs actual behavior
