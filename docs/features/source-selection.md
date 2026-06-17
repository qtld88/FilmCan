# Source Selection

Choose what to copy.

---

## Manual Sources

Drag drives, folders, or files into **Copy From**

Or click **Browse Files...**

---

## Auto-Detect

Automatically add specific drives when connected:

1. Enable **Auto-detect camera sources** (or **Auto-detect sound sources** for sound)
2. Add drive/folder names (supports `*` wildcards)

Auto-detected sources are never removed automatically. Sound auto-detect also tags the
matched drives as Sound.

---

## Camera / Sound (Netflix routing)

Each source card has a small **clickable icon at the top-right** marking it Camera or
Sound:

- **🎥 video-camera** → Camera (lands in `Camera_Media/` under the Netflix preset)
- **🔊 speaker** → Sound (lands in `Sound_Media/`)

**Click the icon to switch** between the two — it's a toggle. Sources default to Camera.
The **Save To** preview updates to show where each source will land. This only changes
the destination folder; it has no effect unless you use a preset with separate camera
and sound folders (e.g. **Netflix Ingest**).

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
