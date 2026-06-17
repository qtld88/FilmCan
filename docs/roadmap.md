# Roadmap

Where FilmCan is heading. Not a promise of dates — a direction. Order is rough priority, not a schedule.

---

## Shipped

- **1.3.0** — Netflix Camera/Sound routing (per-source toggle, sound auto-detect, editable folder templates), ASC MHL vs simple hidden hash list, per-destination resume + full-job progress, live per-destination failure surfacing.
- **1.2.x** — Single Swift copy engine (FanOut), rsync engine removed, ASC MHL chain of custody.

---

## Next

### Automatic media classification
Detect **video vs sound clips** by container/extension and route them automatically, so the Camera/Sound tag no longer has to be set by hand on every source.

### Corrupted-file detection
Go beyond checksum-mismatch: flag clips that are **structurally broken** (truncated, unreadable headers) during or after copy, and surface them per destination.

### PDF backup report (Foolcat-style)
Generate a **delivery-ready PDF** per backup — per-roll thumbnails, clip metadata, checksums, and copy summary — written into the shoot-day `Reports/` folder alongside the transfer log.

---

## Want to influence this?

Open an issue or start a discussion on [GitHub](https://github.com/qtld88/FilmCan). Real-world camera-card workflows shape what gets built first.
