# Options

Options are grouped into tabs in the **Backup Editor**.

> The copy-engine picker was removed in 1.2.0 — the FilmCan Engine handles every
> backup. See [Copy Engines](./copy-engines.md).

---

## Basic options

See [Copy Engines](./copy-engines.md) for engine behavior.

- **Verification** — `Off`, `Fast`, or `Paranoid`. Default for new projects is
  `Fast`. See [Copy Engines](./copy-engines.md#verification-modes).
- **Force re-copy** — re-copies every file even if it's already backed up
  (disables resume skip). Off by default.
- **Duplicate policy** — `Skip`, `Overwrite`, `Add counter`, `Ask each time`. See [Destination Presets](./destination-presets.md).
- **Counter style** — shown only when **Duplicate policy** is `Add counter`.
- **Copy mode** — how multiple destinations are written:
  - `Automatic` *(default)* — parallel for SSDs / distinct drives, sequential for a network destination or two destinations on the same physical volume.
  - `All destinations at once` — read the source once, write everywhere together.
  - `One destination at a time` — copy each destination fully before the next (re-reads the source per destination).
- **Copy order** — `Default order`, `Smallest first`, `Largest first`, `Creation date`.

---

## Source

See [Source Selection](./source-selection.md) for patterns and auto-detect details.

- **Auto-detect sources** — toggle.
- **Drive and folder names to detect** — shown when **Auto-detect sources** is on.
- **Copy folder contents only** — copies the contents of a source folder without the top-level folder.
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

## Verification & integrity

- **Verification** mode (Off / Fast / Paranoid) is in **Basic options** above.
- **xxHash128** is the checksum algorithm; hash lists are written per source
  root. See [Hash Lists](./hash-lists.md).
- Resume skip and **Force re-copy** are covered in [Copy Engines](./copy-engines.md#resume--re-running-skips-whats-already-there).

> The rsync-only **Transfer refinements** tab was removed in 1.2.0 along with the
> rsync engine.
