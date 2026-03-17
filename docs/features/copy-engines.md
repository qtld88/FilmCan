# Copy Engines

FilmCan offers two copy engines:

- **rsync** — mature and flexible, supports incremental sync and custom filters
- **FilmCan Engine** — fast, simple, optimized for local backups with built-in verification

Both can verify files and create hash lists (FilmCan Engine always verifies).

---

## FilmCan Engine

**How it works:**
1. Copy file while computing source checksum
2. Verify by computing destination checksum
3. Verification runs in background while next file copies

**Features:**
- Automatic parallel file copy on fast SSDs
- Optimized for ExFAT (larger buffers)
- Always verifies

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
