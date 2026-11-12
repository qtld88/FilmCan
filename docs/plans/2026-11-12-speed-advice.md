# Plan — speed advice before and after the copy

Spec: `docs/specs/2026-11-12-speed-advice.md`

| # | Task | Files | Test first |
|---|------|-------|-----------|
| 1 | One pure rule for "one destination at a time?", used by the run | `Models/SpeedAdvice.swift` (`DestinationCopyPlan`), `ViewModels/TransferViewModel.swift` | `SpeedAdviceTests`: same answers as before for every mode, network, shared volume |
| 2 | Advice builder: drive facts in, ≤ 3 advices out, ordered, dismiss keys, action result | `Models/SpeedAdvice.swift` | `SpeedAdviceTests` |
| 3 | After-copy sentence | `Models/SpeedAdvice.swift` (`SpeedNote`) | `SpeedAdviceTests` |
| 4 | Drive facts probe (kind, bus, hub, space), dismiss store | `Services/SpeedAdviceProbe.swift` | dismiss store tested; IOKit hub read manual |
| 5 | Hooks: note computed at the end of a run; band + sentence on the main screen; action applied through the editor view model | `ViewModels/TransferViewModel.swift`, `ViewModels/BackupEditorViewModel.swift`, `Views/Components/SpeedAdviceBand.swift`, `Views/BackupEditor/BackupEditorView+Overview.swift` | action tested on the view model |
| 6 | Manual gate V1–V10 | `docs/smoke-qa-checklist.md` | — |

After merge: run `xcodegen generate` (new files).
