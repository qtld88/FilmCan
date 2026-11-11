# Work tracking — `qt1/*` lots

Living status file for the autonomous lot-by-lot work on `next`. One lot = one `qt1/<name>` branch = one draft PR to `next`. This branch (`qt1/suivi`) only carries this file.

**Session active since 2026-11-11 13:24 UTC** (refreshed every 30–60 min while a session is working; a newer session that reads a timestamp younger than 90 minutes must stop without changing anything).

| # | Lot | Branch | PR | State | Next action |
|---|-----|--------|----|-------|-------------|
| 0 | First-launch defaults: volume-access dialog text, card auto-detect on for new films, PDF report on for new films | `qt1/first-launch-defaults` | #2 | done (green: run 43027920645) | owner: real-app checks F1–F7 |
| 1 | Phone notifications by QR code (simple mode) + static site page | `qt1/phone-qr` | — | task 6 of 6 (pushed, waiting for CI + cold review) | open PR once green |
| 2 | More camera families: generic DCIM, Insta360, AVCHD, P2 | `qt1/more-cameras` | — | spec | write spec and plan |
| 3 | Copy of every report on the Mac | `qt1/reports-on-mac` | — | to do | spec |
| 4 | Calmer main screen: shoot day in header, summary line, less chrome, history as list | `qt1/calm-main-screen` | — | to do | spec |
| 5 | Film owns its settings, "start from a previous film", settings side panel | `qt1/film-settings` | — | to do | spec |
| 6 | Visual folder-structure editor ("new" badges first) | `qt1/folder-tree-editor` (stacked on 5) | — | to do | spec |
| 7a | Recognition settings page | `qt1/recognition-page` (stacked on 5) | — | to do | spec |
| 7b | Re-create a report after the fact | `qt1/recreate-report` | — | to do | spec |
| 8 | Demo mode for users | `qt1/demo-mode` | — | to do | spec |
| 9 | Speed advice before and after the copy | `qt1/speed-advice` | — | to do | spec |

States: `to do`, `spec`, `plan`, `task n of m`, `done`, `blocked`.

## Notes

- Proof for every lot is a green run of the `macOS tests` workflow on the branch's last commit.
- Owner-only checks (real hardware, lid-closed sleep test, real-app visual pass) are listed in each PR under "À vérifier à l'œil" and in `docs/smoke-qa-checklist.md`.
