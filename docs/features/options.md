# Options

Options are grouped into tabs in the **Backup Editor**.  
The **Transfer refinements** tab appears only when **Copy engine** is set to `rsync`.

---

## Basic options

See [Copy Engines](./copy-engines.md) for engine behavior.

- **Copy engine** — choose `rsync` or `FilmCan Engine`. See [Copy Engines](./copy-engines.md).
- **Copy folder contents only** — copies the contents of a source folder without the top-level folder.
- **Automatic parallel copy** — FilmCan Engine only.
- **Duplicate policy** — `Skip`, `Overwrite`, `Add counter`, `Verify using hash list`, `Ask each time`. See [Destination Presets](./destination-presets.md).
- **Counter style** — shown only when **Duplicate policy** is `Add counter`.
- **Copy mode** — `One destination at a time` or `All destinations at once`.
- **Copy order** — FilmCan Engine only: `Default order`, `Small files first`, `Large files first`, `Creation date (oldest first)`.

---

## Source

See [Source Selection](./source-selection.md) for patterns and auto-detect details.

- **Auto-detect sources** — toggle.
- **Drive and folder names to detect** — shown when **Auto-detect sources** is on.
- **Copy-only patterns (optional)**.
- **Include patterns (optional)**.
- **Exclude patterns (optional)**.

---

## Destinations

See [Destination Presets](./destination-presets.md) for templates and tokens.

- **Auto-detect destinations** — toggle.
- **Drive and folder names to detect** — shown when **Auto-detect destinations** is on.
- **Folder template** — toggle + template field.
- **Rename only patterns (optional)** — shown when **Folder template** is on.
- **File name template** — toggle + template field.
- **Custom date for tokens** — toggle + date picker. See [Smart Date](./smart-date.md).

---

## Logs

- **Create log file** — toggle.
- **Location** — `Same as destination` or `Custom folder` (when **Create log file** is on).
- **Custom log folder** — shown when **Location** is `Custom folder`.
- **Log file path and name** — shown when **Create log file** is on.

---

## Transfer refinements (rsync only)

See [rsync Details](./rsync.md) for rsync behavior.

- **Verify after copy** — toggle.
- **Only copy new or changed files** — toggle.
- **Checksum algorithm** — fixed to `xxHash128`. See [Hash Lists](./hash-lists.md).
- **Use checksum to verify file contents before copy** — toggle.
- **Update files in place** — toggle.
- **Allow resume after stop** — toggle.
- **Custom rsync arguments** — text field. See [Custom rsync Arguments](./custom-rsync.md).
- **Delete files not in source** — toggle.
