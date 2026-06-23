# FilmCan Real-Hardware Smoke QA Checklist

Run this checklist on a fresh, signed build before every release. Each row is
one independent test. Tick the box only after the result column matches.

## ⛔ RELEASE GATE — non-negotiable

**No release ships until the Gate block below is run on a real build and every
box is ticked.** Green unit tests + static review are NOT sufficient: every
defect in 1.3.2 (wrong default verify mode, false "not enough space" on the
internal drive, frozen progress bar) passed all unit tests and code review
because they only manifest at runtime, on real volumes, with the UI rendered.
Unit tests run in temp dirs on one volume and never render SwiftUI — they
structurally cannot catch these. The smoke run is the only thing that can.

| # | Gate check (run the actual .app) | Expected | Pass? |
|---|---|---|---|
| G1 | **New-tab default verify mode.** Create a brand-new backup tab, open Options → Verification. | Mode reads **Fast** by default (never Paranoid). | ☐ |
| G2 | **Space preflight vs Finder (internal drive).** Pick a destination on the internal APFS drive. Note Finder's "Available". Start a copy whose size is comfortably under Finder-free but possibly over strict statfs (e.g. 15 GB when Finder shows >40 GB free). | No false "Not enough space"; the number FilmCan shows is within a few % of Finder's Available, not tens of GB lower. Job runs. | ☐ |
| G3 | **Live progress movement.** Start a ≥10 GB copy to a real EXTERNAL drive (ideally a slow/HDD one). Watch the destination card for the first 30 s. | The copy bar, byte counter, speed, and ETA all visibly advance within a few seconds and keep moving — never frozen at 0 while bytes are clearly being written. | ☐ |
| G4 | **Throughput sanity.** During G3, compare observed MB/s to the drive's known write speed. | Within ~2× of the drive's real speed; not pathologically stalled by backpressure. | ☐ |
| G5 | **Purgeable space warning (same-disk / snapshot-heavy).** On a drive where Finder shows ample free but `df -h` (statfs) shows less than the job needs (mostly local snapshots), start a backup to it. | An OVERRIDABLE warning appears explaining Finder shows more than is usable now (snapshots/caches) and a real backup needs real bytes — with Continue Anyway. FilmCan does NOT silently fail at 26%: either the kernel reclaims as it writes and it completes, or it blocks/aborts cleanly. Cross-volume backup to a normal external drive shows no such warning and just works (Finder-parity). | ☐ |
| G6 | **Green verify bar steady + present in Fast.** Watch the destination card on a Fast-mode run, then a Paranoid run. | Fast: green verify bar tracks the yellow copy bar as it goes (inline stream verify) and completes on the disk re-read — steady, never flashing in/out. Paranoid: green advances during the separate verify pass, steady. Off mode: no green bar at all. | ☐ |

If any Gate row fails, the release is blocked — fix and re-run, do not ship.

## Setup

- macOS 14 or later, Apple Silicon and Intel both covered.
- Hardware on hand:
  - SD-card reader with a real cinema card (Sony XAVC, RED .R3D, BMD BRAW, ARRI ProRes — at least one).
  - Two external SSDs (USB 3.2+ or Thunderbolt), different brands.
  - One external HDD (USB 3, spinning, exFAT) to exercise the slow / `F_FULLFSYNC` path.
- FilmCan app: built `Release` configuration, signed with Developer ID, installed in `/Applications`.

## Test matrix

| # | Scenario | Source kind | Dests | Verify mode | Expected | Pass? |
|---|---|---|---|---|---|---|
| 1 | Single file → 2× SSD | flat 5 GB MOV | SSD-A, SSD-B | paranoid | Both green checkmarks, MHL on each, no `.filmcan-*` orphans, throughput ≈ slowest dest write speed | ☐ |
| 2 | Card directory → 2× SSD | mounted card root | SSD-A, SSD-B | paranoid | Recursive tree mirrored under `<dest>/<cardName>/`, one MHL per source root with full file list, sealed `<sealed/>` tag | ☐ |
| 3 | Card directory → SSD + exFAT HDD | mounted card root | SSD-A, HDD-exFAT | paranoid | "DO NOT UNPLUG" banner visible while HDD active, both complete, HDD throughput visibly lower | ☐ |
| 4 | Multi-source job | 3 separate clips + 1 card dir | SSD-A, SSD-B | paranoid | Aggregate bytes counter monotonic (no rewinds), per-dest tile shows correct file N/M, all sources land at correct dest paths | ☐ |
| 5 | Fast mode | card dir | SSD-A, SSD-B | fast | Both finish faster than paranoid run; tiles show sealed checkmark (fast also stream-verifies) | ☐ |
| 6 | Cancel mid-copy | flat 20 GB clip | SSD-A, SSD-B | paranoid | Stop button kills both writers cleanly; no orphans in dest dirs; partial MHL shows `<filmcan:partial reason="…"/>` | ☐ |
| 7 | Insufficient free space | flat 100 GB clip | SSD with 50 GB free | paranoid | Pre-flight blocks the job with red "Not enough space" message; no temp files created | ☐ |
| 8 | One dest fails mid-copy | card dir | SSD-A (good), SSD-B (unplug at 50%) | paranoid | SSD-A completes & verifies; SSD-B shows ✗ + Retry button; `FailedDestRetryPanel` mounts; pressing Retry opens `RetryRepairSheet` | ☐ |
| 9 | Repair from sibling | continuation of #8 (re-plug SSD-B) | — | paranoid | Choose "From sibling"; all SSD-B files copied + hash-verified from SSD-A; row flips to green checkmark; MHL on SSD-B matches SSD-A | ☐ |
| 10 | Repair from source | continuation of #8 (SD card still mounted) | — | paranoid | Choose "From source"; SSD-B re-copied from source card with full paranoid re-read; row flips green | ☐ |
| 11 | Source unplugged mid-job | card dir | SSD-A, SSD-B | paranoid | Both dests report I/O failure with clear reason text; no half-written final files (only sealed `.filmcan-*` orphans, cleaned on next run) | ☐ |
| 12 | Dest unplugged at finalize | flat 5 GB | SSD-A (unplug after copy, before fsync) | paranoid | Failure surfaced; nothing reported as `success`; MHL marked partial | ☐ |
| 13 | Power-loss simulation | flat 10 GB → exFAT HDD | HDD-exFAT | paranoid + `F_FULLFSYNC` required | After hard reboot mid-copy: no half-written final filenames; only `.filmcan-*` orphans (which the next run cleans) | ☐ |
| 14 | Webhook v1 + v2 | any small job, v1 then v2 | SSD-A, SSD-B | fast | v1: one ntfy / webhook per dest. v2 (`webhookTemplateFormatVersion = 2`): single aggregated event with both dest summaries | ☐ |
| 15 | App relaunch mid-job | flat 50 GB | SSD-A, SSD-B | paranoid | Force-quit FilmCan during copy. Relaunch. Next run cleans `.filmcan-*` orphans from dests | ☐ |
| 16 | Off verify mode | card dir | SSD-A, SSD-B | off | Copy completes; tiles reach 100% + Complete; **no MHL written** on either dest | ☐ |
| 17 | Resume skip | re-run of #2 (unchanged) | SSD-A, SSD-B | fast | **No new history card** — "Already backed up" popup; "Verify data" matches all files | ☐ |
| 18 | Resume — partial | #2 source + one new clip added | SSD-A, SSD-B | fast | Only the new clip copies; row reads "Resuming — N files already backed up…"; a history card is added | ☐ |
| 19 | Resume — deleted file | #2, delete one file from SSD-B | SSD-A, SSD-B | fast | Only the deleted file is re-copied to SSD-B (presence check, not just MHL) | ☐ |
| 20 | Force re-copy | #2 with Force re-copy ON | SSD-A, SSD-B | fast | Every file re-copied; nothing skipped | ☐ |

## Post-run sanity checks

- `find /Volumes/<dest> -name ".filmcan-*"` returns nothing after a clean job.
- Every successful copy has exactly one `.filmcan/hashlists/<root>.mhl` per source root, sealed.
- Open each MHL in a text editor and confirm one `<hash>` block per file.
- `xxh128sum` (or `mhlfile verify` if available) on a few destination files matches the value in the MHL.

## Known limitations to verify did NOT regress

- The FilmCan Engine is the only user-facing engine (rsync retired from the UI in
  1.2.0). There is no engine picker to test; rsync code is dormant.
- Sandbox stays disabled (entitlement file `com.apple.security.app-sandbox = false`).
- Drive speed classifier still flags exFAT external as "slow flush required" so the `DO NOT UNPLUG` banner appears.
