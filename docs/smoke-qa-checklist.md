# FilmCan Real-Hardware Smoke QA Checklist

Run this checklist on a fresh, signed build before every release. Each row is
one independent test. Tick the box only after the result column matches.

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

## Post-run sanity checks

- `find /Volumes/<dest> -name ".filmcan-*"` returns nothing after a clean job.
- Every successful copy has exactly one `.filmcan/hashlists/<root>.mhl` per source root, sealed.
- Open each MHL in a text editor and confirm one `<hash>` block per file.
- `xxh128sum` (or `mhlfile verify` if available) on a few destination files matches the value in the MHL.

## Known limitations to verify did NOT regress

- Rsync engine path (Copy Engine = Rsync) must still work end-to-end for backwards compatibility.
- Sandbox stays disabled (entitlement file `com.apple.security.app-sandbox = false`).
- Drive speed classifier still flags exFAT external as "slow flush required" so the `DO NOT UNPLUG` banner appears.
