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
| G7 | **Nav responsiveness.** Build DEBUG, run `log stream --predicate 'subsystem == "com.filmcan.app"'`. With an external drive mounted, switch Film tabs, switch Options tabs (esp. Destinations), add/remove sources & dests. | No `MainThreadWatchdog: HANG` (>500ms) lines attributed to the drive/list regions (`sourceDriveNodes`, `destinationDriveNodes`, `sourceListSummaries`, `destListSummaries`, `getFileMetadata`). NOTE: residual `region='idle'` hangs from heavy editor view-body construction are a known, separately-tracked issue (see technical-debt) — not a release blocker yet. | ☐ |
| G8 | **Auto-update check.** Build version N (current `main`), install it. Bump `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in `project.yml`, build version N+1, run `package_release.sh` for N+1 pointing `SUFeedURL` at a local/staging copy of the resulting `appcast.xml` (see spec Testing section). Launch version N, wait for the background check or trigger **Check for Updates…**. | Update alert appears with N+1's release notes; Install downloads, verifies the EdDSA signature, installs, and relaunches as N+1 with no crash. Confirm whether a Gatekeeper "unidentified developer" prompt appears on the relaunch (ad-hoc-signed app, not notarized) — record the answer either way; it is not a failure by itself, but it must be known before advertising auto-update to users. | ☐ |

If any Gate row fails, the release is blocked — fix and re-run, do not ship.

### Quick Copy gate (run when Quick Copy / Services code changed)

| # | Check (real .app, installed once) | Expected | Pass? |
|---|-----------------------------------|----------|-------|
| Q1 | Quit FilmCan. Finder: right-click a **folder** → Services → **FilmCan Copy**. | Quick Copy window opens; no main window (≤ 1 s flash tolerated); Dock icon visible. | ☐ |
| Q2 | Same with a **single file**, then with a **mounted card**. | Window opens; Camera/Sound pre-filled sensibly; Run works. | ☐ |
| Q3 | Quit FilmCan. Drop a folder on the **Dock icon**. | Same window; no second main window. | ☐ |
| Q4 | Two destinations, Project + day, Camera + Sound items, Run. | `YYYYMMDD_Project_Day/Camera_Media/<roll>` and `/Sound_Media/<roll>` on both, `ascmhl/` per roll, copy+verify bars move, both cards ✓. | ☐ |
| Q5 | **Show in Finder**, then **Close**. | Finder reveals the day folder; FilmCan quits (launched for quick copy). | ☐ |
| Q6 | With the main app open and a normal backup running, start a quick copy. | Both run; closing the quick copy does NOT quit FilmCan. | ☐ |
| Q7 | Start a quick copy, **Stop**, run it again to the same destination. | Second run resumes and copies only what is missing. (Stop, not Pause — Pause does not exist in Quick Copy) | ☐ |
| Q8 | During a quick copy press ⌘Q; and close the window. | Quit alert / "Stop the copy?" alert; Continue keeps copying. | ☐ |
| Q9 | After a completed quick copy. | macOS notification (and ntfy if configured) received; entry present in `history.json`. | ☐ |
| Q10 | Preset = a saved preset with `Ask each time`. | The preset chips show *Skip existing files* (tooltip explains the mapping); no prompt appears. | ☐ |
| Q11 | After a Services-launched quick copy, quit, then open FilmCan normally. | Main window opens at its usual size/position (not the Quick Copy window's frame); no Quick Copy window. | ☐ |
| Q12 | Close the main window, click the Dock icon (no quick copy involved). | Exactly one main window reopens, as before this feature. | ☐ |
| Q13 | Quick Copy window → "Edit in FilmCan…" with the main window closed/hidden. | Main window appears; closing the quick copy afterwards does NOT quit FilmCan. | ☐ |
| Q14 | Netflix Ingest preset, source folder named with a prohibited character (e.g. `A001 (copy)`). | Run disabled with a message naming the characters. | ☐ |
| Q15 | File › New Window (⌥⌘N), then ⌘B in the front window. | A second main window opens; only ONE backup starts (front window's film). | ☐ |
| Q16 | File › New Quick Copy Window (⇧⌘N) right after launching FilmCan normally. | Empty Quick Copy window; main window stays visible; closing it does NOT quit FilmCan. | ☐ |
| Q17 | Eject icon next to a source/destination (main window card and Quick Copy row), no copy running. | Drive ejects; unsealed card asks first; Quick Copy drops every row on that drive. | ☐ |
| Q18 | During a copy: eject icon, context-menu Eject, and Finder's eject button on the card and on the backup drive. | App icons greyed (tooltip says why); Finder refuses ("in use"). After the run ends, Finder ejects normally. | ☐ |

### First-launch defaults gate (run when new-film defaults or Info.plist usage texts changed)

| # | Check (real .app) | Expected | Pass? |
|---|-------------------|----------|-------|
| F1 | In Terminal: `tccutil reset All com.filmcan.app`. Launch FilmCan, add a camera card as a source. | The macOS dialog "FilmCan would like to access files on a removable volume" shows a sentence explaining why. | ☐ |
| F2 | Same reset, then pick a folder inside Documents, then Desktop, then Downloads. | Each macOS dialog shows its own explaining sentence. | ☐ |
| F3 | Plug a camera card. Click "+" to create a new movie. | The card appears in Copy From by itself, tagged Camera (a sound recorder card: Sound). | ☐ |
| F4 | In the new movie: Options › Source and Options › Logs. | "Detect camera and sound cards automatically" is on; "PDF report with thumbnails" is on. | ☐ |
| F5 | Open a movie that existed before this build. | Both switches are as you left them. | ☐ |
| F6 | New movie, one real card, one drive, run the backup. Time it. Switch the PDF report off, wipe the destination folder, run again, time it. | A `_report.pdf` sits next to the log after the first run. Note the time difference (thumbnail extraction). | ☐ |
| F7 | Finder › right-click a folder › Services › FilmCan Copy, run it. | No PDF report is written (Quick Copy is unchanged). | ☐ |

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

### Movie settings gate (run when presets or movie creation changed)

Before the first launch of this build, keep a copy of `configs.json` and `presets.json` (Application Support › FilmCan).

| # | Check (real .app) | Expected | Pass? |
|---|-------------------|----------|-------|
| S1 | Launch on existing data where two movies use the same preset. | Both movies show the same preset name, same folder preview as before. No "(modified)" mark. | ☐ |
| S2 | Run a backup of an existing movie with an existing card. | Same folders and files as with the previous build (resume finds everything). | ☐ |
| S3 | In movie A, change the folder template. Open movie B. | B's template and folder preview are unchanged. | ☐ |
| S4 | Preset menu in a movie. | Lists "Off", "Netflix Ingest (built-in)", the shared presets once each (no duplicates), "Save as new preset", "Delete preset". | ☐ |
| S5 | Choose a preset in movie A, edit a folder, then choose the same preset in movie B. | B gets the preset as saved, not A's edit. | ☐ |
| S6 | "Save as new preset" in movie A. | A new preset appears in the menu of every movie; A keeps its settings. | ☐ |
| S7 | Choose "Off", open the menu again, choose "This movie's settings (…)". Then press the trash button next to the preset name. | Off then back: the movie's own folders return unchanged. Trash: the movie goes to "Off" for good; the shared preset is still in the menu. | ☐ |
| S8 | "Delete preset" › a preset. | It leaves the menu; movies that started from it keep their folders. | ☐ |
| S9 | Small arrow next to "+" in the tab bar › "Like <movie>". | A new movie with the same options, no cards, no drives, empty shoot day. File › New Movie Like shows the same list. | ☐ |
| S10 | Movie "Citizen K" with template `CITIZENK/{day}`; create a movie like it and rename it "Citizen L". | The new movie's template starts with `{movie}`; the preview shows `Citizen L/…`. The old movie still writes to `CITIZENK/…`. | ☐ |
| S11 | Type `{movie}` in a folder template (it is in the token list). | The preview shows the movie's name. | ☐ |
| S12 | Delete a movie, quit, open `presets.json`. | No record with that movie's `ownerFilmId` remains. | ☐ |
| S13 | Quick Copy: pick a movie, look at the Preset picker; pick another movie. | The picker shows the shared presets plus the picked movie's own settings, never another movie's. | ☐ |
| S14 | Settings › Import & Export › Presets › Export. | The file holds the shared presets only. | ☐ |
| S15 | Export a movie, delete it, import it back. | Same preset name, same folder preview as before the export. | ☐ |

### Settings layout gate (run when the settings panel or the Settings window changed)

| # | Check (real .app, window at 1280 × 800) | Expected | Pass? |
|---|-------------------|----------|-------|
| L1 | Look under Copy From / Save To. | One line: gear, "Movie settings", a short summary. No tab bar, no Options card. | ☐ |
| L2 | Click the line. | A panel opens on the right with Basic / Source / Destinations / Logs and the Preset menu. Copy From and Save To are still visible and readable. | ☐ |
| L3 | In the panel, change the folder layout. | The folder preview in Save To follows at once. | ☐ |
| L4 | Go through the four groups. | Every setting that was in the Options card is there; nothing is clipped or overlapping at the panel's width. | ☐ |
| L5 | With the panel open, open History, then Catalog. Then click the line again. | The panel closes when History or Catalog opens; clicking the line closes that pane and opens the panel. | ☐ |
| L6 | Panel open, switch movie tab; quit and relaunch. | The panel stays open and shows the current movie's settings. | ☐ |
| L7 | Panel closed, choose a preset from… (open the panel, close it, use File or the menu as before). | Choosing a preset opens the panel. | ☐ |
| L8 | Narrow the window to its minimum. | Cards stack, the panel keeps a usable width, nothing overlaps. | ☐ |
| L9 | Run the quick tour. | The former "Options Tabs" step highlights the "Movie settings" line. | ☐ |
| L10 | Open Settings (Cmd+,). | A sidebar with Appearance, Notifications, Phone & webhooks, History, Drives, Shortcuts, About; each page shows what its tab showed. Reopen Settings: the last page is selected. | ☐ |
| L11 | Read the labels in Basic and Destinations. | "Full check (re-reads every file)", "If a file already exists", "Checksum list format", "Folder layout", "Rename files", "Custom date in names". | ☐ |
| L12 | Run a backup; open its log and history entry. | Same wording as before in logs and history (only the settings labels changed). | ☐ |

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
