# Source Selection

Choose what to copy.

---

## Manual Sources

Drag drives, folders, or files into **Copy From**

Or click **Browse Files...**

---

## Auto-Detect

Automatically add specific drives when connected:

1. Enable **Auto-detect sources**
2. Add drive/folder names (supports `*` wildcards)

Auto-detected sources are never removed automatically.

---

## Include / Exclude Patterns

**Include** (copy only these):
```
*.R3D
*.MOV
*.BRAW
```

**Exclude** (skip these):
```
*.tmp
*/Cache/
```

**Copy-only** (copy only these, keep folder structure):
```
*.R3D
*.BRAW
```

**Default excludes**: `.DS_Store`, `.Trashes`, `.Spotlight-V100`, `.fseventsd`, `.DocumentRevisions-V100`, `.TemporaryItems`

Include runs first, then exclude.

---

## Troubleshooting

**Source not appearing**  
Check if mounted + grant Full Disk Access

**Wrong files copied**  
Review include/exclude patterns

---

## Related

- [Quick Start](../quickstart.md)
- [Options](./options.md)
