# Multi-Destination Backups

Back up to multiple destinations for redundancy. The FilmCan Engine reads the
source **once** and writes to every destination together; the **Copy mode**
option chooses how those writes are scheduled.

---

## Copy mode

Set in **Backup Editor → Options → Copy mode**.

### Automatic *(default)*

FilmCan picks per run: **parallel** when destinations are distinct SSDs, and
**sequential** when a destination is a network volume or two destinations live on
the same physical volume (parallel writes to one drive thrash it). It does **not**
gate on the OS "solid state" flag, which is unreliable for external USB /
Thunderbolt SSDs.

### All destinations at once (parallel)

Source is read once and broadcast to every destination in parallel. Throughput
is set by the slowest drive — the others overlap their writes. One read pass per
source regardless of destination count.

### One destination at a time (sequential)

Copy each destination fully before the next. Gentler on a shared bus or hard
drives, but re-reads the source once per destination.

Each destination still gets one sealed ASC-format MHL per source root, and a
failed drive can be repaired without restarting the others.

---

## Setup

1. Add multiple destinations in **Save To** (drag drives or click **Add another destination**)
2. Pick the **Copy mode** in Options (default **Automatic** is usually right)
3. Drag destinations to reorder

---

## Behavior

- Each destination card shows its own progress bar, percent, bytes copied / total, speed, ETA, and verify phase
- A drive that requires `F_FULLFSYNC` (typically exFAT, USB HDDs, some externals) shows an orange **DO NOT UNPLUG** badge while active
- Verification of one file overlaps the copy of the next (see [Copy Engines](./copy-engines.md#verify-pipeline))
- If one destination fails, the others continue
- When the run finishes with at least one failed destination, the **Retry repair panel** appears under the progress

---

## Repair after a failure (FilmCan Engine only)

If a drive fails mid-job, you don't have to start over. After the run, the failed row has a **Retry** button. Pressing it opens the repair sheet:

- **From source** — if the original source(s) are still mounted, FilmCan re-runs the fan-out engine for that single drive.
- **From sibling** — FilmCan reads the verified neighbor drive's MHL, copies each listed file to the failed drive, and hash-verifies as it goes. The source card no longer needs to be mounted. This is the cinema set workflow: keep going, fix the drive at lunch.

The **From sibling** option only enables when at least one other destination from the same job succeeded.

---

## Drive speed warning

If FilmCan detects that destinations have very different expected throughputs (e.g. one Thunderbolt SSD and one USB-2 HDD), it shows a heads-up — the slow drive will pace the whole job in fan-out mode. The warning is informational; the copy proceeds.

---

## Related

- [Copy Engines](./copy-engines.md)
- [Hash Lists](./hash-lists.md)
- [Stop](./stop.md)
- [Push Notifications](./push-notifications.md)
