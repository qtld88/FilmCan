# Plan — more camera families

Spec: `docs/specs/2026-11-11-more-cameras.md`

| # | Task | Files | Test first |
|---|------|-------|-----------|
| 1 | Generic DCIM rule with its own bounded video search | `FilmCan/Sources/Services/CameraCardDetector.swift` | `CameraCardDetectorTests`: with video, video directly in DCIM, photos only, empty, hidden file, beyond the scan cap, Canon/GoPro/DJI win, WAV next to clips |
| 2 | Insta360, AVCHD, Panasonic P2 rules | same | fixtures per family; Canon XF not P2; AVCHD + Sony / + Panasonic keep their brand |
| 3 | `CameraBrand.recognisedBy` | same | every case has a name and a sentence; only the sound recorder is sound |
| 4 | User docs (4 languages), manual gate | `docs/features/source-selection.md`, `docs/smoke-qa-checklist.md` | — |

Existing tests are not edited. No new file: `xcodegen generate` is not needed for this lot.
