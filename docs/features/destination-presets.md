# Destination Presets

Organize files with folder structures, renaming, and duplicate handling.

---

## Example

```
Folder: {date}/{source}/
Rename: {source}_{counter}{ext}
Duplicates: Add counter
```

Result:
```
20260315/A001/
  A001_001.R3D
  A001_002.R3D
```

---

## Variables

**Source / Destination**  
`{source}` — original source name (file or folder)  
`{sourceParent}` — parent folder name of the source  
`{sourceDriveName}` — drive containing the source  
`{destinationDriveName}` — drive containing the destination  
`{destination}` — destination folder name

**Dates / Time**  
`{date}` — `YYYYMMDD`  
`{time}` — `HHmmss`  
`{datetime}` — `YYYYMMDD-HHmmss`  
`{filecreationdate}` — file creation date (`YYYYMMDD`)  
`{filemodifieddate}` — file modified date (`YYYYMMDD`)

**File Info**  
`{filename}` — source filename without extension  
`{ext}` — file extension (includes the dot)

**Counter**  
`{counter}` — incrementing counter (`001`, `002`, `003`…)

---

## Duplicate Handling

| Option | Behavior |
|--------|----------|
| **Skip** | Keep existing file |
| **Overwrite** | Replace existing file |
| **Add counter** | Add suffix like `_001` |
| **Verify using hash list** | Compare to existing hash list before writing |
| **Ask** | Prompt every time |

**Note:** Hash lists are created only when **Hash verification** is enabled (FilmCan Engine) or when rsync verification is enabled.

---

## Custom Day Boundary

Shooting past midnight? Use [Smart Date](./smart-date.md) to set a custom day start.

---

## Related

- [Smart Date](./smart-date.md)
- [Options](./options.md)
