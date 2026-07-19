# Quick Start

Get your first backup running quickly.

---

## 1. Create a Backup

Click **+** in the top bar (or press `⌘N`)

---

## 2. Add Sources

Drag your card or folder into **Copy From**

Or click **Browse Files...**

---

## 3. Add Destinations

Drag one or more drives into **Save To**

Or click **Browse Folders...**

> **Why multiple?** Redundancy. If one drive fails, you have another.

---

## 4. Run

Click **Run Now**

FilmCan will:
- Copy files to all destinations
- Hash-verify every byte (when enabled)
- Generate a hash list for later verification (when hash verification is enabled)

Results appear in **Transfer History** (click the **clock** icon)

---

## Optional: Basic options

Want a bit more control before you run? Open **Options → Basic** and set:

- **Verification**: Fast (default) or Paranoid, a full re-read after copy
- **Duplicate policy**: what happens when a file already exists at the destination
- **Copy mode**: all destinations at once, or one at a time

[Learn more →](./features/options.md)

---

## Optional: Organization

Want files organized by date or card? Open **Options → Destinations** and set a **Folder template** for that destination, e.g. `{date}/{source}/`. No preset needed, just fill in the template.

[Learn more →](./features/destination-presets.md)

---

## Notes

- FilmCan stores history locally on your Mac.
- Transfers require read access to sources and write access to destinations.

---

## Next Steps

- [Features Overview](./features/index.md)
- [Transfer History](./features/transfer-history.md)
- [Troubleshooting](./troubleshooting.md)
