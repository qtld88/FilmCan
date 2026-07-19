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

---

## Preflight Space Warning

When destinations do not have enough space, you’ll see one of:

- `Not enough space on <name>.\n\nNeeded: <bytes>\nAvailable: <bytes>\n\nThe backup may fail or be incomplete.`
- `Not enough space on <count> destinations: <names>.\n\nThe backup may fail or be incomplete on these drives.`

---

## Copy and Verify Errors

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
