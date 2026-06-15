# Netflix Footage Ingest & ASC MHL — Requirements Memento + FilmCan Gap Analysis

Condensed from Netflix Partner Help (Production Assets Data Management, Footage
Ingest: Preparing Media, Footage Ingest: Folder Template) and the ASC MHL spec
(github.com/ascmitc/mhl). Use as the reference for making FilmCan output
"Netflix-ingest-ready".

---

## A. The requirements (condensed)

### Copies & media
- **≥ 3 copies** of all OCF (original camera files) + OPA (original production audio).
- **≥ 2 different media types**; **≥ 1 copy off-site** (different geographic location).
- RAID 5/6/10+ for backup; **RAID 0 only for shuttle/transfer, never backup**.
- LTO (if used): generations 6–9, **LTFS v2.0.0+**. Max **100 rolls or 10 TB per upload dir**.

### Checksums & manifest
- **Accepted hashes: xxHash64BE, xxHash128, or MD5.**
- **ASC MHL** is the recommended manifest format. One **MHL per roll**, generated at offload.
- MHL sits at the **roll directory root**: `…/A001/A001.mhl` or `…/A001/ascmhl/A001.mhl`.
- **Reel name = the folder directly above the MHL.**
- Roll is **sealed** after creation — don't modify; recreate/update if files change.
- **Verify after every copy** against the original checksums; chain of custody from
  the first offload through every subsequent copy to archive.

### Folder template (Netflix)
- Root: **`YYYYMMDD_EP###_Day##_Unit`** (e.g. `20230510_EP103_Day05_MU`).
  - Episode field: `Block##` / `B##` / `BK#` / `EP###` (omit for features/multi-ep single day).
  - Day field: `Day###` / `D##` / `D###` / `##`.
  - Unit: MU/1U (main), SU/2U (second), TU/3U (third), SP, UU/PU (pickup), AP, RS, DU (drone), AU (array).
- Subdirs: **`Reports/`**, **`Camera_Media/[optional Camera_Format/]<Roll>/`**, **`Sound_Media/`**.
- Each camera/sound roll in **its own folder, nested under a parent** (never at root).
- **Prohibited filename chars:** ``@ # $ % ^ & * ( ) ` ; : < > ? , [ ] { } / \ ' " | ~``. Roll names unique.

### Drives / handling
- **APFS preferred; avoid exFAT.** NVMe/M.2 SSD, USB-C/TB, 10 Gbps+. Reformat before offload.
- Dest drive **not slower than source**. QC from a checksum-verified safety copy (not the card), 3840×2160+.

### ASC MHL format (vs legacy MHL v1.1)
- `ascmhl/` folder per directory holds: per-generation XML manifests + **`ascmhl_chain.xml`** (verification history).
- **Generations**: each copy/verify appends a new manifest generation → chain of custody, detects renamed/missing files, directory hashes from contained files.
- XML carries **creatorinfo** (author, location, tool, timestamp) + file records (path, size, hash).
- Hashes supported by ASC MHL: **xxHash (64 / XXH3-64 / XXH3-128), MD5, SHA1, C4**.
- Reference tooling: `mhllib`, `ascmhl` CLI (create generation / verify / flatten).

---

## B. Where FilmCan stands today

| Area | Netflix wants | FilmCan now | Verdict |
|------|---------------|-------------|---------|
| Checksum | xxHash64BE / xxHash128 / MD5 | **xxHash128** | ✅ already compliant |
| Manifest format | ASC MHL (ascmhl XML + chain) | custom XML (`<file name>`,`<hash>`,`<sealed/>`,`<filmcan:partial>`) | ❌ not ASC-MHL-spec |
| MHL location | `<roll>/<roll>.mhl` or `<roll>/ascmhl/<roll>.mhl` (roll root) | `<dest>/.filmcan/hashlists/<rootName>.mhl` (hidden, not per-roll) | ❌ wrong place |
| One MHL per roll | yes | one per source root (close, but not roll-folder-anchored) | ⚠️ partial |
| Verify every copy | yes | Fast/Paranoid per run | ✅ |
| Chain of custody / generations | yes (ascmhl_chain) | single sealed MHL, no generations | ❌ |
| Folder template | `YYYYMMDD_EP###_Day##_Unit/{Reports,Camera_Media/<Roll>,Sound_Media}` | free tokens `{source}`,`{date}`,… ; no `{episode}`/`{day}`/`{unit}` | ❌ no built-in preset |
| Filename validation | prohibited-char set, unique rolls | none | ❌ |
| Drive guidance | APFS, avoid exFAT, ≥3 copies, 2 media | exFAT/F_FULLFSYNC banner; fan-out to N dests | ⚠️ partial |

**Answer to "MHL vs checksum vs folder naming?"** → **Checksum is already fine** (xxh128
is accepted). The real gaps are **(1) the MHL** (format + on-disk location must match
ASC MHL / Netflix), and **(2) folder naming** (a built-in Netflix preset + filename
validation). MHL is the single biggest lever.

---

## C. Recommended improvements (priority order)

1. **Adopt the ASC MHL format + roll-root location** *(highest value)*
   - New `ASCMHLWriter` emitting spec XML: `<hashlist version="2.0">` with `<creatorinfo>`
     (tool=FilmCan, version, host, ISO-8601 start/finish) and `<hashes><hash><path size=…>`
     `<xxh3 …>` per file. Seal = a complete generation.
   - Write to **`<roll>/ascmhl/<NNNN>_<roll>.mhl`** at the roll root (the roll folder being
     the organization-preset root), not `.filmcan/hashlists`. This makes "reel name = folder
     above MHL" work and the output directly ingestable.
   - Keep `MHLReader` working for the resume-skip/Verify paths (read both old + ASC MHL).
   - *Stretch:* `ascmhl_chain.xml` with multi-generation appends so a re-copy/verify adds a
     generation rather than rewriting — true chain of custody.

2. **Built-in "Netflix Ingest" organization preset + new tokens**
   - Tokens: `{episode}`/`{block}`, `{day}`, `{unit}`, `{cameraFormat}`, plus existing `{date}`.
   - Folder template: `{date:YYYYMMDD}_{episode}_{day}_{unit}/Camera_Media/{cameraFormat}/{roll}`
     and auto-create sibling `Reports/` + `Sound_Media/`.
   - Land the transfer **log/report into `Reports/`** when this preset is active (ties into the
     log work just done).

3. **Filename / roll-name validation**
   - Reject or offer-to-sanitize the prohibited-char set; enforce unique roll names; warn when a
     roll would be split across dirs or a dest exceeds **100 rolls / 10 TB**.

4. **Delivery-readiness guidance (soft)**
   - Surface a "Netflix-ready" hint: ≥3 destinations, flag if all dests are the same media type,
     prefer APFS, note RAID-0 not-for-backup. Most are advisory banners, cheap to add.

5. **Optional extra hash algorithms** *(low priority — xxh128 already accepted)*
   - Add xxHash64BE and MD5 as selectable algorithms for partners/specs that mandate them.

---

## D. Sources
- Netflix Partner Help — Production Assets Data Management
- Netflix Partner Help — Footage Ingest: Preparing Your Media For Upload
- Netflix Partner Help — Footage Ingest: Folder Template
- ASC MHL spec + reference tools — https://github.com/ascmitc/mhl
