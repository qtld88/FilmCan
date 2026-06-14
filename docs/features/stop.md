# Stop & Resume

Stop a backup and continue later without re-copying what's already done.

---

## Stop

- Click **Stop Backup** (or **Stop Backups**) during a transfer.
- The stop is clean: the file being written is aborted **before** it's finalized,
  so no half-written file is left at the destination. A *"Stopping the backup(s)
  properly…"* indicator shows while the engine finishes aborting.

---

## Resume

- Select the backup and click **Run Now** again.
- Files already recorded in **every** destination's hash list **and** still
  present on disk are skipped. Only the remaining files are copied. The progress
  row reads *"Resuming — N already backed up, copying the rest."*
- A file that was deleted from a destination is re-copied (presence is checked,
  not just the hash list).
- **Force re-copy** (Options) ignores all of this and re-copies everything.

If the whole backup is already present when you press Run, no new history card is
created — an **Already backed up** popup appears instead, with a **Verify data**
button (the same hash-list check as History's *Check data*).

> Caveat: with a `{date}` folder template, resuming on a *different day* re-copies
> into that day's folder (earlier files aren't matched). Use Force re-copy to be
> explicit.

---

## Related

- [Copy Engines](./copy-engines.md)
- [Transfer History](./transfer-history.md)
