# FilmCan

<p align="center"><img src="assets/icon.png" alt="FilmCan Icon" width="160"/></p>
<p align="center"><strong>Professional backup for camera cards.</strong></p>
<p align="center">Fast, verified, and free.</p>

<p align="center">
  <a href="docs/installation.md">Install</a> •
  <a href="docs/quickstart.md">Quick Start</a> •
  <a href="docs/index.md">Docs</a> •
  <a href="docs/faq.md">FAQ</a> •
  <a href="docs/privacy.md">Privacy</a>
</p>

---

## What It Does

FilmCan backs up camera cards, rushes, folders, or files to multiple destinations with verification and organization presets—giving DITs, ACs, and cinematographers peace of mind through battle‑tested rsync and a purpose‑built fan‑out copy engine.

- Copies multiple sources to multiple destinations in one pass (fan-out: source read once, broadcast to every drive)
- Two verify modes: **fast** (stream hash during copy) and **paranoid** (post-copy re-read from disk, bypassing OS cache)
- Honest writes on external/exFAT drives via `F_FULLFSYNC` (forces drive cache flush, not just OS buffers)
- Per-destination ASC MHL hash lists, sealed at job end (cinema standard)
- Auto-detect drives, folders, files — handles cinema card directory trees (RDC, RDM, BRAW, .ari, R3D)
- Live per-destination progress, "DO NOT UNPLUG" banner on slow-flush drives
- One-click **Retry from sibling**: a failed drive rebuilds from a verified neighbor's MHL — no need to re-mount the card
- Organizes files with custom folder presets
- Aggregated webhooks and ntfy push notifications

---

## Quick Start

1. Click **+ New Backup**
2. Drag your card into **Copy From**
3. Drag drives into **Save To**
4. Click **Run Now**

Done. FilmCan copies, verify and save checksums.

[More details →](docs/quickstart.md)

---

## Install

1. Download the **DMG** from [GitHub Releases](https://github.com/qtld88/FilmCan/releases) (recommended)
2. Open the DMG and drag `FilmCan.app` to **Applications**
3. Open FilmCan (macOS may block the first launch; go to **System Settings → Privacy & Security → Open Anyway**)
4. Grant permissions when prompted

[Full install guide →](docs/installation.md)

---

## Screenshot
<p align="center"><img src="assets/screenshot-main.png" alt="FilmCan Icon" width="600"/></p>

---

## Support

- [Troubleshooting](docs/troubleshooting.md)
- [FAQ](docs/faq.md)
- [Documentation](docs/index.md)
- [Privacy](docs/privacy.md)
- [AI Usage](docs/ai-usage.md)
- [Report a bug](docs/contributing.md)

---

## License

GNU GPL v3.0 — see [LICENSE](LICENSE)

---

<p align="center"><strong>Get it in the can.</strong></p>
