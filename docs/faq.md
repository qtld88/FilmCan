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
Choose a Verification mode in Options, `Fast` (default) checks the hash computed during the copy; `Paranoid` re-reads every file from disk. FilmCan uses xxHash128.

**Can I stop and resume?**  
Yes. Stop is clean (no partial files), and running again skips files already backed up to every destination and still present, only the rest is copied. See [Stop & Resume](./features/stop.md).

**Hash lists?**  
Yes. Created automatically unless Verification is Off. See [Hash Lists](./features/hash-lists.md).

---

## Organization

**Organize by date?**  
Yes. Use [Destination Presets](./features/destination-presets.md).

**Shoot past midnight?**  
Use [Smart Date](./features/smart-date.md) to set a custom day boundary.

---

## Technical

**Which copy engine?**  
The FilmCan Engine handles every backup. (rsync was retired from the UI in 1.2.0.) See [Copy Engines](./features/copy-engines.md).

**Config location?**  
`~/Library/Application Support/FilmCan/configs.json`  
`~/Library/Application Support/FilmCan/presets.json`  
`~/Library/Application Support/FilmCan/history.json`

**Will I lose data if I reinstall or upgrade?**  
No, not in normal reinstall/upgrade flows. FilmCan keeps movies, presets, and history in `~/Library/Application Support/FilmCan/`, outside the app bundle.  
If you use cleanup tools that remove Application Support, data can be deleted.

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
See [Report a bug](https://github.com/qtld88/FilmCan/issues) for bug reporting.

---

## See Also

- [Quick Start](./quickstart.md)
- [Troubleshooting](./troubleshooting.md)
- [Support](/#support)
