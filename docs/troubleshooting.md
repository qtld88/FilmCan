# Troubleshooting

Quick fixes for common issues.

For detailed error codes, see [Transfer Errors Reference](./reference/transfer-errors.md).

---

## App Won't Launch

- Right-click > Open (bypass Gatekeeper)
- Check **System Settings** > **Privacy & Security**
- Re-download the DMG
- Restart your Mac

---

## Permissions

**Can't access files**  
**System Settings** > **Privacy & Security** > **Full Disk Access** > Add FilmCan

**No notifications**  
**System Settings** > **Notifications** > FilmCan > Enable

---

## Transfer Issues

**Won't start**  
- Source is mounted and readable
- Destination is writable with free space
- Check safety warnings in the UI

**Stuck or slow**  
- Large files take time (check drive activity)
- Try sequential mode instead of parallel
- Close other disk-intensive apps
- Check cables and drive health

**Incomplete**  
- Check destination has space
- Review logs in Transfer History (if logs are enabled)
- Resume or re-run

---

## Sources & Destinations

**Source not detected**  
- Reconnect card reader
- Try another USB port
- Check if mounted: `/Volumes/`

**Destination full**  
- Free up space or use another drive
- Check permissions

**Wrong organization**  
- Verify organization preset settings
- Check Smart Date (Custom date for tokens)

---

## Verification

**Verification failed**  
- Re-copy the file
- Run **Disk Utility** > **First Aid**
- Try another drive

**Hash list not found**  
- Check the stored path in Transfer History
- Re-run the backup to generate a new hash list

---

## Still Stuck?

- [FAQ](./faq.md)
- [Transfer Errors Reference](./reference/transfer-errors.md)
- [Report a bug](./contributing.md)
