# Multi-Destination Backups

Back up to multiple destinations for redundancy. FilmCan supports three execution strategies; the right one depends on the chosen [Copy Engine](./copy-engines.md).

---

## Modes

### Fan-out (FilmCan Engine)

Source is read **once** and broadcast in parallel to every destination. Throughput is set by the slowest drive — every other drive overlaps its writes. This is the default when **Copy Engine = FilmCan Engine** and there are 2+ destinations.

- One read pass per source, regardless of destination count
- Per-destination tile shows live progress, verify phase, and a "DO NOT UNPLUG" badge on exFAT / external drives that require `F_FULLFSYNC`
- One sealed ASC-format MHL per source root, per destination
- If a drive fails, the others continue; a **Retry** button appears on the failed row

### Sequential (rsync)

One destination at a time. Lower memory footprint. Use when destinations share a bus you don't want to oversubscribe.

### Parallel (rsync)

All destinations spawn their own rsync process at once. Each one re-reads the source independently — fine on fast cards, doubles or triples card-side I/O on slow ones.

---

## Setup

1. Add multiple destinations in **Save To** (drag drives or click **Add another destination**)
2. Pick the **Copy Engine**:
   - **FilmCan Engine** → fan-out is automatic
   - **rsync** → choose **Sequential** or **Parallel** in **Copy Mode**
3. Drag destinations to reorder (priority hint for sequential)

---

## Behavior

- Each destination shows its own progress tile with bytes, speed, ETA, and verify phase
- A drive that requires `F_FULLFSYNC` (typically exFAT, USB HDDs, some externals) shows an orange **DO NOT UNPLUG** badge while active
- If one destination fails, the others continue
- When the run finishes with at least one failed destination, the **Retry repair panel** appears under the progress tiles

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
