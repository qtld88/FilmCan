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
- If using FilmCan Engine with paranoid verify, the failed drive(s) show a **Retry** button under their progress row
- Choose **From sibling** to rebuild the failed drive from a verified neighbor's MHL (the source card no longer needs to be mounted)
- Choose **From source** if the original card is still mounted and you want a fresh re-copy of just that drive
- For rsync: re-copy the file, run **Disk Utility** > **First Aid**, try another drive
- If re-checking from history passes, this was likely a drive write-cache timing issue — the drive didn't fully flush before verify ran. If it happens repeatedly on the same drive, check drive health.

**Hash list not found**
- Confirm the destination is mounted and check `<destination>/.filmcan/hashlists/`
- FilmCan Engine writes one MHL per source root (e.g. `CARD_A001.mhl`) aggregating every file
- Re-run the backup to generate a new hash list
- Hash lists are created automatically by FilmCan Engine, or when rsync verification is enabled

**"DO NOT UNPLUG" banner stays on**
- Some external/USB drives are flagged as requiring full cache flush (`F_FULLFSYNC`)
- The banner clears once the drive's verify phase finishes
- If it persists after the run completes, the drive's cache may not have flushed cleanly — see the os_log warnings in Console.app, filtered to subsystem `com.filmcan.app`

---

## Still Stuck?

- [FAQ](./faq.md)
- [Transfer Errors Reference](./reference/transfer-errors.md)
- [Report a bug](./contributing.md)
