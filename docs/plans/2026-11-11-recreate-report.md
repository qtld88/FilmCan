# Plan — create a report after the fact

Spec: `docs/specs/2026-11-11-recreate-report.md`

| # | Task | Files | Test first |
|---|------|-------|-----------|
| 1 | Report model: "created after the fact" block, per-file note, status line | `FilmCan/Sources/Models/BackupReport.swift` | `ReportRecreationTests`: status never says verified; default report unchanged |
| 2 | Find the roll now, read the checksum list(s), build the report, re-read | `FilmCan/Sources/Services/ReportRecreation.swift` | drive renamed / not connected / no id; listed, size changed, not listed, missing; ASC MHL and simple list on disk; re-read finds a changed file |
| 3 | PDF: header lines, status, missing list, per-file note; shared write step; `recreate` | `FilmCan/Sources/Services/BackupReportWriter.swift` | PDF text of a recreated report; nothing written next to the roll; unreachable roll writes nothing |
| 4 | Catalog menu, progress line, failure alert | `FilmCan/Sources/Views/CatalogView.swift` | view only; manual gate |
| 5 | User doc + manual gate G1–G8 | `docs/features/backup-report.md`, `docs/smoke-qa-checklist.md` | — |

After merge: run `xcodegen generate` (new files).
