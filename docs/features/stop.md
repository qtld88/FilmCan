# Stop & Resume

Stop a backup and continue later. With rsync, you can avoid re‑copying finished files.

---

## How It Works

- With rsync, **Only copy new or changed files** skips completed files on the next run.
- With rsync, **Allow resume after stop** continues partial files when enabled.
- FilmCan Engine restarts the in‑progress file.

---

## Stop

- Click **Stop Backup** (or **Stop Backups**) during transfer

## Resume

- Select the backup and click **Run Now**
- With rsync and **Only copy new or changed files**, FilmCan skips files that already match

---

## Partial File Behavior

- If **Allow resume after stop** is OFF, the in-progress file restarts
- If ON, rsync can continue from the last written byte

---

## Related

- [Transfer History](./transfer-history.md)
