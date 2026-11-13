# Plan — movie settings panel, Settings sidebar, plain labels

Spec: `docs/specs/2026-11-11-film-settings-panel.md`

| # | Task | Files | Test first |
|---|------|-------|-----------|
| 1 | Central labels, Settings pages, panel rules | `FilmCan/Sources/Models/SettingsWording.swift` | `SettingsWordingTests` |
| 2 | Settings window: sidebar instead of tabs | `FilmCan/Sources/Views/SettingsView.swift` | page list tested in task 1; layout in the manual gate |
| 3 | Movie settings line + side panel, one pane at a time | `BackupEditorView.swift`, `BackupEditorView+Options.swift`, `MainView.swift`, `QuickTourView.swift` | rules tested in task 1; layout in the manual gate |
| 4 | Labels use the central wording | `Options/BasicOptionsView.swift`, `Options/DestinationsOptionsView.swift`, `OrganizationSettingsView.swift` | term test in task 1 |
| 5 | Manual gate | `docs/smoke-qa-checklist.md` | — |

After merge: run `xcodegen generate` (new files).
