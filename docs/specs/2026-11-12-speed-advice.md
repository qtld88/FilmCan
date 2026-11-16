# Speed advice, before and after the copy

**Date:** 2026-11-12 · **Lot:** 9 · **Branch:** `qt1/speed-advice`

## Goal

"Why was it slow?" is the first question after a long offload. Answer it before the copy, while the user can still act, and after it, with what was measured.

## Before the copy

A short band under the two columns of the main screen, same style as the existing warning bands. At most three at a time, the one costing the most time first (rough estimate from the drive kinds and the size to copy). Never blocks anything. Each has **Dismiss**; a dismissed advice does not come back for the same drives (kind + volume ids, kept in the preferences). Hidden while the movie is copying.

| Advice | When | Text gist | Action |
|---|---|---|---|
| Slow and fast drives at once | The run writes to every destination at the same time (mode "all at once", or "automatic" when automatic chooses that) and one destination is at least 3× faster than another by drive kind | The copy to every drive goes at the pace of the slow one; copying to the fast one first gives a first checked copy in about X instead of Y, the whole copy takes a little longer | **Copy to ‹fast› first**: mode "one at a time", fast drives moved to the front of Save To |
| Slow drive first | The run copies one destination at a time and a drive at least 3× faster waits behind a slower one | Same estimate | **Copy to ‹fast› first**: fast drives moved to the front |
| USB 2 | A card or drive is on a USB 2 link | About 35 MB/s at most; a USB 3 or Thunderbolt port and cable would be much faster | none |
| Shared USB hub | Two or more different drives (cards included) sit behind the same external USB hub | The hub splits its speed between them; plug one straight into the Mac | none |
| SSD nearly full | An SSD destination would be more than 90 % full after the copy | Many SSDs write more slowly when nearly full | none |

exFAT is not repeated: the existing band covers it. Only the checked (included) cards and drives count.

**Which drives are "slow" or "fast".** macOS often reports an external SSD as "not solid state", so that flag alone never makes a drive slow. A drive is called slow only when it reports a spinning medium ("Rotational") or sits on USB 2; fast only when it reports solid state on USB 3, Thunderbolt or inside the Mac. Anything else is unknown and never named.

**What "automatic" already does (checked in the code):** it copies one destination at a time only for network drives or two destinations on the same volume. A hard drive next to an SSD is copied at the same time, so the first advice is real, not a problem the engine already solves. The decision is moved into one pure function shared by the run and the advice, unchanged.

## After the copy

One sentence under Save To, until the next run of this movie. Only after a run of a movie (not Quick Copy) where every destination succeeded, nothing was cancelled, and at least 1 GB was actually written (a resumed run counts only what it wrote). Times are wall-clock times measured around each pass by the app, check included; the engine's per-file durations are not used (in a run to several drives at once they include waiting for the slowest).

- **One destination at a time:** each pass is timed on its own; with two drives that each wrote at least 1 GB in at least 30 s, name the slowest when it is clearly slower (1.5×): "‘LaCie’ was the slowest drive: 85 MB/s, against 390 MB/s for ‘T7’."
- **All at once:** overall speed = bytes written / whole run time. The slowest known link is named from the drive kinds. If the measured speed is close to what that link allows (the full read-back check counts as halving it): "This copy ran at 48 MB/s, read-back check included. The slowest link was ‘LaCie’ (hard drive)." If every drive is known and the speed is far below what they allow: "…slower than these drives allow. A shared hub, a long cable or a busy Mac may have held it back." Otherwise nothing.

## Edge cases

- Drive kind unknown: treated as unknown, never named as the cause; no advice built on it.
- Two destinations without a volume id are not treated as one volume (same rule as the run).
- Card readers: the hub and USB 2 checks read the reader's link, which is what limits the card.
- Same volume used twice: counted once.
- Network destination: no hub or USB advice for it.
- A drive unplugged after the advice was built: the advice disappears with the next drive refresh.

## What does not change

- Copy engine, verification, manifests: untouched. The run's sequential/parallel choice keeps exactly the same rule (test).
- No stored field is added to a movie. Settings change only when the user clicks an action.
- The order of destinations has no effect on folder names or files (each drive gets the same layout; the duplicate-card check compares cards with each other, not drives). Moving one changes which drive is copied first, which drive "Open logs" opens when logs sit next to the backup, and which drive a run that fails before starting is filed under.

## Decisions

- Advice cost is a rough estimate from typical speeds per drive kind (the figures the engine already uses). Good enough to sort; not shown as a promise.
- "Copy to ‹fast› first" changes the movie's setting for good (visible and reversible in the movie's options), rather than for one run: simpler, and the user can see it.
- Hub detection reads the USB tree (nearest external hub above each drive). It cannot be tested here; real-hardware checks below.

## Success criteria

- HDD + SSD destinations at once → advice with action; after the action, mode is one-at-a-time and the SSD is first (test).
- A dismissed advice does not come back for the same drives, and does for other drives (test).
- At most 3, most costly first (test).
- After-copy sentence follows the rules above (tests on measured inputs).

## Not in this lot

- Measuring the card reader's own speed before the copy; remembering the fastest port.
- Copying from the fast drive to the slow one after the card is done (card → SSD → HDD).
