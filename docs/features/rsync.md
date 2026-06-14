# rsync Under the Hood

> **Retired in 1.2.0.** The rsync engine is no longer selectable in the UI — the
> [FilmCan Engine](./copy-engines.md) handles every backup. This page is kept for
> historical reference.

FilmCan previously could use **rsync**, a proven file transfer tool.

---

## Why rsync

- Mature and reliable
- Efficient incremental transfers
- Built-in checksums
- Industry standard

---

## FilmCan + rsync

FilmCan runs rsync and adds:
- Verification options
- Hash list generation
- GUI progress tracking

---

## Requirements

FilmCan uses a bundled rsync when available, then tries Homebrew rsync, then the system rsync.

If you need newer rsync features, install or upgrade Homebrew rsync:
`brew upgrade rsync`

---

## Related

- [Copy Engines](./copy-engines.md)
- [Custom rsync Arguments](./custom-rsync.md)
- [Hash Lists](./hash-lists.md)
