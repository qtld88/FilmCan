# Plan — the film owns its settings (part 1)

Spec: `docs/specs/2026-11-11-film-settings.md`

| # | Task | Files | Test first |
|---|------|-------|-----------|
| 1 | `OrganizationPreset.ownerFilmId` (optional, decoded with default) | `FilmCan/Sources/Models/OrganizationPreset.swift` | `FilmPresetOwnershipTests`: legacy JSON decodes with nil owner; round trip |
| 2 | Pure adoption logic: clone per film, idempotent; shared-preset filter; removal with the film | `FilmCan/Sources/Models/FilmPresetOwnership.swift`, `FilmCan/Sources/Services/ConfigurationStorage.swift` | adoption table tests; storage round trip in a temp directory |
| 3 | View model: choosing a preset copies it; save-as-preset, Off, trash; Netflix lookup among shared presets | `FilmCan/Sources/ViewModels/BackupEditorViewModel.swift` | two films on one preset: editing one leaves the other and the shared preset unchanged |
| 4 | Lists show shared presets; no "(modified)" for an own copy | `BackupEditorView+Options.swift`, `QuickCopySession.swift`, `QuickCopyViews.swift`, `TransferHistoryView.swift` | list filter tested in task 2 |
| 5 | `{movie}` token | `FilmCan/Sources/Utilities/OrganizationTemplate.swift` and the places that build `ShootMetadata` | resolves; sanitised; templates without it unchanged |
| 6 | "Like a previous movie": `BackupConfiguration.newFilm(name:like:)`, leading-folder rule, `AppState.createNewConfig(like:)` / `(fromPreset:)` | `BackupConfiguration.swift`, `FilmPresetOwnership.swift`, `AppState.swift` | copied vs not copied field lists; leading-folder rule |
| 7 | "+" split control and File menu entries | `BackupListView.swift`, `FilmCanApp.swift` | view only; manual gate |
| 8 | Manual gate | `docs/smoke-qa-checklist.md` | — |

After merge: run `xcodegen generate` (new files).
