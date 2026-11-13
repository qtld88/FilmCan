# Plan — calmer main screen

Spec: `docs/specs/2026-11-11-calm-main-screen.md`

| # | Task | Files | Test first |
|---|------|-------|-----------|
| 1 | Pure logic: `ShootDayStepper`, `RunSubtitle`, `MainScreenChrome` | `FilmCan/Sources/Models/MainScreenSummary.swift` | `FilmCan/Tests/MainScreenSummaryTests.swift` |
| 2 | `BackupEditorViewModel.setShootDayFromHeader` | `FilmCan/Sources/ViewModels/BackupEditorViewModel.swift` | `ShootDayHeaderTests` (counter off; blank and unchanged values ignored) |
| 3 | Header stepper, Run subtitle (summary row removed after the trial) | `FilmCan/Sources/Views/Components/ShootDayStepperView.swift`, `FilmCan/Sources/Views/BackupEditor/BackupEditorView+Options.swift`, `+Overview.swift` | thin views; manual gate |
| 4 | Chrome: path line, order numbers, folded tree | `FilmCan/Sources/Views/SourceListView.swift`, `DestinationListView.swift` | rules tested in task 1 |
| 5 | History list by default | `FilmCan/Sources/Views/TransferHistoryView.swift` | manual gate |
| 6 | Manual gate | `docs/smoke-qa-checklist.md` | — |

After merge: run `xcodegen generate` (new files).
