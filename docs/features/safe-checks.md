# Safe Checks

FilmCan validates setup before each backup to prevent avoidable failures.

---

## What's Checked

- Source exists and is readable
- Destination exists (or can be created) and is writable
- Destination is not read-only
- Free space (pre‑flight warning)
- Delete confirmation when **Delete files not in source** is enabled
- Log and hash list locations are validated; FilmCan warns if they can’t be created

---

## What You'll See

Warnings for:
- Low disk space (you can still continue)
- Log file could not be created (FilmCan continues without a log)
- Hash list could not be created (FilmCan continues without a hash list)

Duplicate handling happens during transfer based on your **Duplicate policy**.

---

## Settings

Source and destination validation always runs.  
Duplicate behavior is set in **Options** under **Duplicate policy**.

---

## Related

- [Options](./options.md)
- [Multi-Destination](./multi-destination.md)
