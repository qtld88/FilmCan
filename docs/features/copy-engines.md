# Copy Engines

FilmCan offers two copy engines:

- **rsync** — mature and flexible, supports incremental sync and custom filters
- **FilmCan Engine** — fast, simple, optimized for local backups with hash verification

Both can verify files and create hash lists (hash verification is optional for FilmCan Engine).

---

## FilmCan Engine

**How it works:**
1. Copy file while computing source hash
2. Verify by computing destination hash
3. Verification runs in background while next file copies

**Limitations:**
- No incremental sync (always copies the full selection)
- No custom rsync arguments (rsync only)
- Resume after pause depends on the setting and file system (rsync only)
- Slower with lots of tiny files (thousands of KB-sized files)

**Features:**
- Automatic parallel file copy on fast SSDs
- Optimized for ExFAT (larger buffers)
- Hash verification can be disabled in **Basic** options

**Future improvements:**
- Optional `fcopyfile()` fast path for small files (speed boost when hash verification is off)

---

## rsync

**How it works:**
1. rsync copies files
2. Optional post-copy verification
3. Hash lists generated during copy

**Use when you need:**
- Incremental sync (only copy changed files)
- Resume support
- Custom rsync arguments

---

## Which Should I Use?

| Use Case | Engine |
|----------|--------|
| Simple local backup | FilmCan Engine |
| Incremental sync | rsync |
| Custom options | rsync |
| Maximum speed | FilmCan Engine |

---

## Related

- [Hash Lists](./hash-lists.md)
- [rsync Details](./rsync.md)
- [Options](./options.md)
