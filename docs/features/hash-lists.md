# Hash Lists

Hash files for later verification. Hash lists are generated for successful transfers when verification is enabled and FilmCan can write the list file.

---

## Limitations

- Hash lists are stored locally on the destination drive.
- If the destination is unavailable, the hash list cannot be re‑verified.

---

## Format

```
# filmcan-hash: xxh128
<xxh128>  <absolute-path>
```

One line per file. Uses xxHash128 hashes.

---

## When Generated

**FilmCan Engine**  
Hashes are captured during verification and written to the hash list (when Hash verification is enabled).

**rsync**  
Hashes are computed in the background as files finish copying.

---

## Location

```
<destination>/.filmcan/hashlists/
```

Filename:
```
hashlist_<config>_<source>_<destination>_YYYYMMDD-HHMMSS.xxh128
```

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
