# Hash Lists

Hash files for later verification. Hash lists are generated for successful transfers when verification is enabled and FilmCan can write the list file.

---

## Limitations

- Hash lists are stored locally on the destination drive.
- If the destination is unavailable, the hash list cannot be re‑verified.

---

## Style: ASC MHL vs Simple

**Options › Basic › Hash list style** picks the manifest format:

| Style | What it writes | For |
|-------|----------------|-----|
| **ASC MHL** (default) | Visible `ascmhl/` folder: a per-generation manifest + `ascmhl_chain.xml` (C4 chain of custody) | Delivery-grade, Netflix-conformant |
| **Simple (hidden)** | One hidden `.filmcan/hashlists/<roll>.mhl` per roll, no chain | Users who just want verification, clean destination |

Resume-skip and verification behave the same either way. The **Netflix Ingest** preset
always forces ASC MHL (the picker is locked).

---

## Format (ASC MHL)

FilmCan writes a spec-faithful **ASC MHL v2.0** manifest per roll (xxHash128 /
xxh3-128 file hashes), plus an `ascmhl_chain.xml` index recording each generation by
its **C4** hash — a chain of custody accepted by the reference ASC MHL tooling.

```xml
<hashlist version="2.0" xmlns="urn:ASC:MHL:v2.0">
  <hashes>
    <hash>
      <path size="…">A001C001.mov</path>
      <xxh128 action="original" hashdate="…">…</xxh128>
    </hash>
  </hashes>
</hashlist>
```

---

## When Generated

The xxHash128 of each file is computed during the copy and written to the manifest
as the file finalizes, unless **Verification** is set to `Off`. Each backup run adds
a new **sealed generation** to the roll's chain.

---

## Location

**ASC MHL** — at each roll's `ascmhl/` folder (the roll = the source-root folder at
the destination):

```
<destination>/<roll-folder>/ascmhl/0001_<roll>_<date>Z.mhl
<destination>/<roll-folder>/ascmhl/ascmhl_chain.xml
```

**Simple** — one hidden file per roll:

```
<destination>/.filmcan/hashlists/<roll>.mhl
```

(Backups made before 1.3 used the `.filmcan/hashlists/` location for all styles;
resume still reads those once.)

---

## Verify Later

1. Open **Transfer History** (click the **clock** icon)
2. Right-click a transfer
3. Choose **Check data**

FilmCan compares files against the saved hashes.

If a transfer is cancelled or fails, or the hash list cannot be written, the list may not be saved.

---

## Related

- [Copy Engines](./copy-engines.md)
- [Transfer History](./transfer-history.md)
- [Options](./options.md)
