# Hash Lists

Checksum files for later verification. Hash lists are generated automatically for every successful transfer.

---

## Format

```
# filmcan-hash: xxh128
<xxh128>  <absolute-path>
```

One line per file. Uses xxHash128 checksums.

---

## When Generated

**FilmCan Engine**  
Hashes are captured during verification and written to the hash list.

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
3. Choose **Check Data**

FilmCan compares files against the saved checksums.

If a transfer is cancelled or fails, a hash list may not be saved.

---

## Related

- [Copy Engines](./copy-engines.md)
- [Transfer History](./transfer-history.md)
- [Options](./options.md)
