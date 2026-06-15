# QA Checklist

Manual test procedure for FilmCan. This validates core flows and checks for doc/UI mismatches. (The FilmCan Engine is the only copy engine; rsync was retired from the UI in 1.2.0.)

---

## Test Setup

1. Create a source folder with a small text file, a medium file (10–100 MB), and a large file (1–5 GB if possible).
2. Create two destination folders on different drives, or two folders on the same drive if only one drive is available.
3. Ensure you can read the source and write to both destinations.

---

## Core Flow

1. In **Options > Basic**, set **Verification** to `Off`. Click **Run Now**. Expected: copy completes; destination card shows 100% and Complete; no hash list written.
2. Set **Verification** to `Fast` and run to a fresh destination. Expected: yellow copy bar fills, green verify overlay; success; MHL written per source root.
3. Set **Verification** to `Paranoid` and run to a fresh destination. Expected: same, plus the "Verifying…" tail on the last file; verification of a file overlaps the next file's copy.
4. Open **Transfer History** (clock icon). Expected: one history card with correct date/time.
5. Right‑click the card and run **Check data** for a destination. Expected: verification report matches the run.

---

## Resume Skip

1. Run a Fast backup of a multi-file source to two destinations; let it finish.
2. Click **Run Now** again (unchanged). Expected: **no new history card** — an **Already backed up** popup appears. Click **Verify data** → report shows all files match.
3. Add one new file to the source and run again. Expected: only the new file copies; the row shows *"Resuming — N already backed up, copying the rest"*; a history card is added.
4. Delete one already-backed-up file from a destination and run. Expected: only that file is re-copied (presence check).
5. Turn **Force re-copy** ON and run. Expected: every file is re-copied; no skip.

---

## Duplicate Handling

1. Run the same backup again with the same sources/destinations.
2. Set **Duplicate policy** to **Skip** and run. Expected: existing files remain unchanged.
3. Set **Duplicate policy** to **Overwrite** and run. Expected: timestamps update and file contents are replaced.
4. Set **Duplicate policy** to **Add counter** and run. Expected: new file names are created with a counter suffix.
5. Set **Duplicate policy** to **Ask each time** and run. Expected: a duplicate prompt appears for each conflict.

---

## Netflix Ingest preset

1. In **Options**, pick **Preset > Netflix Ingest (built-in)**. Expected: the **Shoot
   metadata** fields appear (Destinations tab); the log location defaults to `Reports/`.
2. Set Episode `EP103`, Day `Day05`, Unit `MU`, Camera format `ARRI`. Add a card folder
   `A001` and a destination. Run.
3. Expected dest tree: `20260615_EP103_Day05_MU/Camera_Media/ARRI/A001/…`, plus sibling
   `Reports/` and `Sound_Media/`, an `A001/ascmhl/0001_A001_<date>Z.mhl` + `ascmhl_chain.xml`,
   and the transfer log in `Reports/`.
4. Run again unchanged. Expected: a new generation `0002_…` is added to the chain.
5. Name a source `B:01`. On Run, the validation sheet appears. Click **Auto-fix & run**.
   Expected: the source folder is renamed to `B_01` and the backup proceeds.
6. With fewer than 3 destinations, the metadata section shows the ≥3-copies reminder.

---

## Stop / Cancel

1. Start a transfer with several large files.
2. Click **Stop Backup** (or **Stop Backups**) during copy. Expected: a *"Stopping the backup(s) properly…"* indicator shows; the run stops within a few seconds; affected destinations show cancelled (red); no `.filmcan-*` orphans and no half-written final files in the destinations.
3. Click **Run Now** again. Expected: files completed before the stop are skipped (resume); only the rest copy.

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
4. Verify a hash list exists at `<destination>/.filmcan/hashlists/` (unless **Verification** is `Off`).
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
