# Plan — first-launch defaults

Spec: `docs/specs/2026-11-11-first-launch-defaults.md`

| # | Task | Files | Test first |
|---|------|-------|-----------|
| 1 | Add five file-access usage descriptions | `FilmCan/Sources/Info.plist` | `FilmCan/Tests/InfoPlistUsageDescriptionTests.swift` reads the host app bundle and requires each key |
| 2 | `BackupConfiguration.newFilm(name:)` with card detection and PDF report on; `AppState.createNewConfig()` uses it | `FilmCan/Sources/Models/BackupConfiguration.swift`, `FilmCan/Sources/Services/AppState.swift` | `BackupConfigurationCodableTests`: new-film values, differs from plain init by two fields only, legacy JSON stays off, switched-off round trip, plain init unchanged |
| 3 | User docs (4 languages) and manual checks | `docs/features/source-selection.md`, `docs/features/backup-report.md`, `docs/smoke-qa-checklist.md` | — |

After merge: run `xcodegen generate` (one new test file).
