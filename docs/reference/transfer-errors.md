# Transfer Errors Reference

This page lists the current user‑facing messages FilmCan emits, based on the app code.

Where messages appear:
- **Validation alerts** before a transfer starts.
- **Destination cards** during/after transfer (`TransferResult.errorMessage`).
- **Warning line** on destination cards (`TransferResult.warningMessage`).
- **History > Check data** alert sheet.

---

## Preflight Validation (Before Transfer)

These are shown as alerts in the Backup Editor:

- `Please add at least one source file or folder`
- `Please add at least one destination folder`
- `Source does not exist: <path>`
- `Permission denied: Cannot read source <name>`
- `Destination is read-only (<format>): <path>`
- `Cannot create destination folder: <path>\n<error>`
- `Permission denied: Cannot write to <name>`
- `Invalid custom rsync arguments`

---

## Preflight Space Warning

When destinations do not have enough space, you’ll see one of:

- `Not enough space on <name>.\n\nNeeded: <bytes>\nAvailable: <bytes>\n\nThe backup may fail or be incomplete.`
- `Not enough space on <count> destinations: <names>.\n\nThe backup may fail or be incomplete on these drives.`

---

## rsync Transfer Errors

These messages come from rsync stderr parsing:

- `Destination drive is full. Free up space and try again.`
- `Destination is read-only. Remount with write access or choose another drive.`
- `Protected macOS system folders were skipped (expected).` (warning)
- `Permission denied: Cannot read some source files. Check file permissions.`
- `Permission denied: Cannot write to destination. Check folder permissions.`
- `Source file or folder no longer exists. It may have been moved or unmounted.`
- `Destination path no longer exists. The drive may have been disconnected.`
- `Drive error: Unable to read or write files. The drive may be failing or was disconnected.`
- `Source files changed during transfer. Some files were modified or deleted while copying.`
- `Some files are in use and cannot be copied. Close applications using these files and try again.`
- `Network error: Cannot connect to destination. Check network connection.`
- `Connection timeout: Destination is not responding. Check if the drive is still connected.`

---

## rsync Exit Code Mapping

When rsync exits with these codes, FilmCan returns:

- **1**: `Syntax or usage error in rsync command`
- **2**: `Protocol incompatibility or version mismatch`
- **3**: `Error selecting input/output files or directories`
- **4**: `Unsupported action requested`
- **5**: `Error starting client-server protocol`
- **6**: `Rsync error: <first stderr line>` or a multi‑line message with chmod/chown guidance if stderr is empty
- **9**: `Rsync was killed by the system (signal 9). Common causes include macOS quarantine/Gatekeeper, low memory, or security software. Move FilmCan to /Applications and open it once, or remove quarantine, then retry.`
- **9**: `Rsync error (code 9). The process was terminated unexpectedly (possible causes: quarantine, low memory, or security software).`
- **10**: `Error in socket I/O`
- **11**: `Error in file I/O (may indicate drive disconnection)`
- **12**: `Error in rsync protocol data stream`
- **13**: `Error with program diagnostics`
- **14**: `Error in IPC code`
- **20**: `Received SIGUSR1 or SIGINT`
- **21**: `Some error returned by waitpid()`
- **22**: `Error allocating core memory buffers`
- **23**: `Partial transfer: Some files were successfully transferred, but some failed. Check the log for failed files: <log file>`
- **23**: `Partial transfer: Some files were successfully transferred, but some failed. Enable logs to see which files failed.`
- **24**: `Partial transfer: Some files were not transferred (vanished before transfer). Check the log for failed files: <log file>`
- **24**: `Partial transfer: Some files were not transferred (vanished before transfer). Enable logs to see which files failed.`
- **25**: `Maximum number of file deletions limit reached`
- **30**: `Timeout waiting for data`
- **35**: `Timeout in data send/receive`
- **Other**: `Transfer failed (exit code <code>)\n<stderr>`

---

## rsync Launch / Verification Errors

- `Failed to launch rsync: <error>`
- `rsync failed: rsync not found. FilmCan bundles Homebrew rsync (3.4.0+). Rebuild the app with Homebrew rsync installed, or install rsync via Homebrew.`
- `rsync not found for verification.`
- `Post-copy verification failed: files differ between source and destination`
- `Post-copy verification failed: <error>`
- `Post-copy verification failed: <count> files differ between source and destination`

---

## FilmCan Engine Errors (Custom Engine)

These are surfaced as destination card errors:

- `Stopped by user`
- `Cancelled by user`
- `Copy failed.`
- `Verification failed for <N> files`
- `Cannot read source file: <path>`
- `Cannot write to destination: <path>`
- `Copy failed: Failed to read source: <error>`
- `Copy failed: Failed to write destination: <error>`
- `Copy failed: Failed to read file for verification: <error>`
- `Copy failed: xxHash128 unavailable. Ensure libxxhash is bundled.`

Warnings:

- `Hash list could not be written: <error>`
- `Could not remove partial file at <path>: <error>`

---

## History > Check Data Messages

- `Failed to read hash list.`
- `Hash list missing for this backup`
- `Hash list not found on disk`
- `Verified <N> file(s). All files match.`
- `Verified <N> file(s). <missing> missing, <mismatched> mismatched.`
