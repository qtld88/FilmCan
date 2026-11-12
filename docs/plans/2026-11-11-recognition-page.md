# Plan — Recognition page

Spec: `docs/specs/2026-11-11-recognition-page.md`

| # | Task | Files | Test first |
|---|------|-------|-----------|
| 1 | Page content: sentences, families from the detector's enum | `FilmCan/Sources/Models/RecognitionGuide.swift` | `RecognitionGuideTests`: every `CameraBrand` on the page with name + sentence |
| 2 | Memory accessors: list corrections, remember drive name + date, forget one roll name | `FilmCan/Sources/Services/RollNumberer.swift` (`CardRoleOverrides`, `RollNumberingStore`), `ViewModels/BackupEditorViewModel.swift` (passes the drive name) | `CardRoleOverridesTests` (own preferences suite, old-format entry), `RollMemoryForgetTests` (temp file) |
| 3 | Lists for the page: corrections, rolls per movie | `RecognitionGuide.swift` (`RecognitionMemory`) | `RecognitionMemoryTests`: order, names, deleted movies |
| 4 | Page view + sidebar entry | `Views/RecognitionSettingsView.swift`, `Models/SettingsWording.swift`, `Views/SettingsView.swift` | `SettingsWordingTests` (page list); view is manual gate |
| 5 | User doc + manual gate R1–R8 | `docs/features/source-selection.md`, `docs/smoke-qa-checklist.md` | — |

After merge: run `xcodegen generate` (new files).
