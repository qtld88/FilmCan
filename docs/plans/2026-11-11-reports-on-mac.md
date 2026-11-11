# Plan — a copy of every report on the Mac

Spec: `docs/specs/2026-11-11-reports-on-mac.md`

| # | Task | Files | Test first |
|---|------|-------|-----------|
| 1 | `ReportArchive`: preferences, folder layout, safe names, which checksum lists, copy with replace | `FilmCan/Sources/Services/ReportArchive.swift` | `FilmCan/Tests/ReportArchiveTests.swift` (real temp-dir files) |
| 2 | Call it after each report is written | `FilmCan/Sources/ViewModels/TransferViewModel.swift` | covered by `archive(...)` tests: switched off, drive untouched |
| 3 | Settings › History › Reports section | `FilmCan/Sources/Views/Settings/ReportArchiveSettingsSection.swift`, `FilmCan/Sources/Views/SettingsView.swift` | view only; manual gate R1, R6, R7 |
| 4 | User docs (4 languages), manual gate | `docs/features/backup-report.md`, `docs/smoke-qa-checklist.md` | — |

After merge: run `xcodegen generate` (new files).
