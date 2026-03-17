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

**Webhook not working**  
- Check the webhook URL and internet connection
- Verify your endpoint accepts JSON POST requests

---

## Transfer Issues

**Won't start**  
- Source is mounted and readable
- Destination is writable with free space
- Check safety warnings in the UI

**Error details**  
- During a run, FilmCan shows the failure reason under each destination’s progress bar.  
- After a run, the same reason is stored in Transfer History.

**Stuck or slow**  
- Large files take time (check drive activity)
- Try sequential mode instead of parallel
- Close other disk-intensive apps
- Check cables and drive health

**Incomplete**  
- Check destination has space
- Review the log file at the configured log folder (if logs are enabled)
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
 - If using FilmCan Engine, confirm **Hash verification** is enabled

**Hash list not found**  
- Confirm the destination is mounted and check `<destination>/.filmcan/hashlists/`
- Re-run the backup to generate a new hash list
 - Hash lists are created only when **Hash verification** is enabled (FilmCan Engine) or when rsync verification is enabled

---

## Still Stuck?

- [FAQ](./faq.md)
- [Transfer Errors Reference](./reference/transfer-errors.md)
- [Report a bug](./contributing.md)
