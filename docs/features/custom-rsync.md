# Custom rsync Arguments

Add extra rsync flags when you need them.

---

## Where

**Backup Editor** > **Options** > **Custom rsync Arguments**

---

## Examples

**Exclude files:**
```bash
--exclude='*.tmp' --exclude='.DS_Store'
```

**Limit bandwidth (KB/s):**
```bash
--bwlimit=50000
```

**Include only specific types:**
```bash
--include='*.R3D' --include='*.MOV' --exclude='*'
```

---

## Safety

- Test with small backup first
- Remove args if transfers fail
- Check `man rsync` for syntax

---

## Related

- [rsync Details](./rsync.md)
- [Troubleshooting](../troubleshooting.md)
