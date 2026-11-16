# Plan — visual folder layout editor

Spec: `docs/specs/2026-11-11-folder-tree-editor.md`

| # | Task | Files | Test first |
|---|------|-------|-----------|
| 1 | Tree model: parse / write back, rows, landing marks, edits, starting points | `FilmCan/Sources/Models/FolderStructure.swift` | `FolderStructureTests`: round trips, not-editable list, rows, each edit, reference structures from menus only, resolution through `OrganizationTemplate.resolve` |
| 2 | Where the layout lives (Netflix fields vs the movie's own settings); own record for a movie on "Off" | `FolderStructure.swift` (`FolderLayoutSource`), `Options/OrganizationEditorModel.swift`, `BackupEditorViewModel.swift` | `FolderLayoutSourceTests`, `FolderStructureWritingTests` (temp-directory storage) |
| 3 | Editor view, mounted above the text field | `Views/Components/FolderStructureEditor.swift`, `Options/DestinationsOptionsView.swift` | view only; manual gate |
| 4 | "new" mark in the folder preview | `Models/FolderTreeBuilder.swift`, `Views/Components/FolderTreePreview.swift` | rule tested in `FolderLayoutSourceTests` |
| 5 | Manual gate | `docs/smoke-qa-checklist.md` | — |

After merge: run `xcodegen generate` (new files).
