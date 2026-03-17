# FAQ

---

## Basics

**What is FilmCan?**  
Professional backup for camera cards. Copies to multiple drives with optional hash verification.

**Is it free?**  
Yes. GPL-3.0 licensed.

**Supported macOS?**  
13.0 (Ventura) and later.

---

## Compatibility

**Does it work with my camera?**  
It should work with any camera that mounts as storage (RED, ARRI, Sony, Canon, Panasonic, Blackmagic, GoPro, etc.).

**Network drives?**  
Not officially supported. Local drives are recommended.

---

## Verification

**How do I verify backups?**  
Enable hash verification in Options. FilmCan uses xxHash128 hashes.

**Can I stop and resume?**  
Yes for rsync runs when **Allow resume after stop** is enabled. FilmCan Engine restarts the current file on resume. See [Stop & Resume](./features/stop.md).

**Hash lists?**  
Yes. Created automatically when hash verification is enabled. See [Hash Lists](./features/hash-lists.md).

---

## Organization

**Organize by date?**  
Yes. Use [Destination Presets](./features/destination-presets.md).

**Shoot past midnight?**  
Use [Smart Date](./features/smart-date.md) to set a custom day boundary.

---

## Technical

**rsync or custom copier?**  
Both available. See [Copy Engines](./features/copy-engines.md).

**Config location?**  
`~/Library/Application Support/FilmCan/configs.json`

**Custom rsync arguments?**  
Yes. See [Custom rsync](./features/custom-rsync.md).

**Does it upload anything?**  
No file uploads. Transfers stay local; optional notifications (ntfy/webhook) only send status metadata.

---

## Troubleshooting

**Can't access files**  
Enable Full Disk Access:  
**System Settings** > **Privacy & Security** > **Full Disk Access**

**Slow or failed backup**  
See [Troubleshooting](./troubleshooting.md).

**Report a bug**  
See [Contributing](./contributing.md) for bug reporting.

---

## See Also

- [Quick Start](./quickstart.md)
- [Troubleshooting](./troubleshooting.md)
- [Support](./support.md)
