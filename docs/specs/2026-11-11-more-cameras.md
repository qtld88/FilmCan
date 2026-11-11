# More camera families

**Date:** 2026-11-11 · **Lot:** 2 · **Branch:** `qt1/more-cameras`

## Goal

Card recognition knows cinema cameras well but misses what a newcomer is most likely to plug in: a photo camera, a drone, a phone, an action camera, a camcorder. Recognise those too, without changing what is recognised today.

## Expected behaviour

`CameraCardDetector.detect` keeps its order (first match wins) and gains four rules, all after the existing named families and before the sound rule.

| Family | Rule | Brand |
|---|---|---|
| Panasonic P2 | `CONTENTS/CLIP` and `CONTENTS/VIDEO` both exist | `.panasonic` (existing brand) |
| Insta360 | a `.insv` / `.insp` file within the scan, or a `DCIM/CameraNN` folder | `.insta360` (new) |
| AVCHD | `PRIVATE/AVCHD` or `AVCHD/BDMV` | `.avchd` (new) |
| Generic DCIM | `DCIM/` holds at least one video file, directly or one folder down | `.genericDCIM` (new), shown as "Camera card" |

Rules for generic DCIM:

- A named family always wins (Canon, Panasonic, GoPro, DJI, Insta360 are tested before it).
- A `DCIM` volume with no video file is not proposed as a camera card.
- The video search is separate from the general scan (which stops at 2 000 entries), so a clip behind thousands of photos is found. It looks at up to 64 `DCIM` subfolders.
- Hidden names (`._clip.mp4`) do not count.
- The existing "Not a camera card" correction remains the safety net for a wrong proposal.

Each `CameraBrand` also gets `recognisedBy`, one plain sentence saying what on the card triggers it. A later settings page lists the families from the enum; a test fails if a case lacks a name or a sentence.

## What changes for cards recognised today

One label only: a card with `PRIVATE/AVCHD` and no Panasonic marker (`PANA_GRP`, `_PANA`) was labelled "Panasonic card"; it is now "AVCHD card". Its role (camera), auto-add behaviour and roll naming are identical: none of the new rules returns a reel name, and only `isSound` and `reelName` feed anything beyond the badge.

## What does not change

- Rules and order for ARRI, RED, Sony, Canon, Panasonic, Blackmagic, GoPro, DJI, sound.
- The sound rule and its own video-extension list (a WAV + MOV folder is still "not a card" unless it sits in `DCIM`).
- The copy engine, roll numbering, saved corrections (`CardRoleOverrides`), configuration format.
- Nothing is auto-added unless the film's card detection switch is on.

## Edge cases

- Canon XF (`CONTENTS/CLIPS001`) stays Canon: P2 needs the exact folder `CLIP` plus `VIDEO`.
- AVCHD plus `M4ROOT` stays Sony; AVCHD plus `PANA_GRP` stays Panasonic.
- A camera that writes a separate `.WAV` next to each clip in `DCIM` is a camera card, not a sound card.
- A backup drive with a `DCIM` folder holding video at its root is proposed as a card. Accepted: one right-click dismisses it for good.
- Android's `DCIM/Camera` (no digits) is not Insta360; with video it is generic DCIM.

## Not verifiable here

No real cards. The layouts come from the makers' published folder structures and are reproduced as fixtures in the tests; a real-card pass is in the PR checklist.

## Success criteria

- Fixture tests for each new family and for every "named family wins" pair.
- Photo-only and empty `DCIM` give no card.
- Every existing detector test passes unmodified.
