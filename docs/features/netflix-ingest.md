# Netflix Footage Ingest

FilmCan can produce delivery-ready output for **Netflix Footage Ingest** — the
required folder structure plus a conformant **ASC MHL** manifest per roll.

---

## Quick start

1. In **Options**, open the **Preset** menu and choose **Netflix Ingest (built-in)**.
2. The **Shoot metadata** fields appear (in the Destinations tab). Fill in:
   - **Episode / Block** — e.g. `EP103`, `Block01`, `B01`, `BK1`
   - **Day** — e.g. `Day05`, `D05`
   - **Unit** — e.g. `MU` (main), `2U` (second), `SP`, `PU`, `DU` (drone)…
   - **Camera format** — e.g. `ARRI`, `RED` (optional; the segment is omitted if blank)
3. Add your camera-card sources and destinations, then **Run Now**.

---

## What you get

For a card `A001` shot on 2026-06-15, EP103, Day 5, Main unit, ARRI:

```
20260615_EP103_Day05_MU/
├── Reports/                         ← auto-created (the transfer log lands here)
├── Sound_Media/                     ← auto-created
└── Camera_Media/
    └── ARRI/
        └── A001/
            ├── …copied clips…
            └── ascmhl/
                ├── 0001_A001_2026-06-15_…Z.mhl   ← ASC MHL v2.0 manifest (this generation)
                └── ascmhl_chain.xml              ← generation chain (chain of custody)
```

- **Root folder**: `YYYYMMDD_EP###_Day##_Unit`.
- **One ASC MHL per roll**, at the roll's `ascmhl/` folder. The reel name is the
  folder directly above `ascmhl/` (Netflix's rule).
- Each backup run adds a **new sealed generation** to the chain.

---

## Hashes & conformance

- FilmCan hashes with **xxHash128** (xxh3-128) — one of Netflix's accepted formats.
- The manifest is **ASC MHL v2.0**; the chain file uses **C4** hashes, matching the
  ASC MHL specification. FilmCan's output is accepted by the reference `ascmhl` tool.

---

## Naming validation

When the Netflix Ingest preset is active, FilmCan pre-flights your roll (source
folder) names against Netflix's prohibited-character set and uniqueness rule. If a
name is invalid or duplicated, a sheet offers:

- **Auto-fix & run** — renames the source folders (prohibited chars → `_`, duplicates
  get a numeric suffix) and runs.
- **Run anyway** — proceeds unchanged.
- **Cancel**.

Prohibited characters: `` @ # $ % ^ & * ( ) ` ; : < > ? , [ ] { } / \ ' " | ~ ``

---

## Delivery readiness

Netflix recommends **≥ 3 copies** on **≥ 2 media types**, with **≥ 1 off-site**. The
metadata section shows a reminder of how many destinations you've configured. Add
more destinations (fan-out is one pass) to make extra copies.

---

## Notes

- Logs: selecting the preset pre-fills the log location to `Reports/` (changeable in
  **Options › Logs**).
- exFAT destinations trigger the existing "DO NOT UNPLUG" banner; Netflix prefers APFS.

## Related

- [Copy Engines](./copy-engines.md) · [Hash Lists](./hash-lists.md) · [Destination Presets](./destination-presets.md)
- `docs/reference/netflix-asc-mhl-requirements.md` — the full requirements memento.
