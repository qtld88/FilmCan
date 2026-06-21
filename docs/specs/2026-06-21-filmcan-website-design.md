# FilmCan Website — Design Spec

**Date:** 2026-06-21
**Status:** Approved
**Scope:** Phase 1 — single static landing page. Phase 2 (wiki) documented, not built.

## Goal

A lightweight static website where people can see how FilmCan works, download it,
read a Q&A, find a contact email, reach the GitHub repo, and donate. Visual design
follows the in-app Kodak theme.

## Non-Goals (V1)

- Wiki / deep documentation pages (phase 2)
- Contact form (mailto only)
- Analytics / tracking
- Internationalization
- Any framework or build toolchain

## Hosting & Deployment

- **Host:** GitHub Pages, repo `qtld88/FilmCan`.
- **Source folder:** `website/` (keeps repo root and existing `docs/*.md` untouched).
- **Deploy method:** GitHub Actions workflow using `actions/upload-pages-artifact`
  + `actions/deploy-pages`, publishing `website/` on push to `main`.
  Rationale: Pages branch-deploy only allows root or `/docs`; Actions allows an
  arbitrary folder, so `website/` can stay separate from the markdown docs.

## Tech Stack

Hand-written static **HTML + CSS + vanilla JS**. No framework, no bundler, no build
step. Space Grotesk loaded from Google Fonts CDN (system-ui fallback). Rationale:
matches scope, zero dependencies, trivial to host and maintain.

## File Layout

```
website/
  index.html      # single page, all sections
  styles.css      # Kodak theme tokens + layout
  main.js         # FAQ accordion, smooth scroll, fetch + apply version.json
  version.json    # { "version": "1.3.1", "tag": "Release_1.3.1",
                  #   "dmg": "FilmCan-1.3.1-universal.dmg" } — generated
  assets/
    icon.png            # 1024 app icon (copied from xcassets)
    favicon.png         # generated from icon (sips)
    apple-touch-icon.png# generated from icon (sips)
    og-image.png        # social share image, generated from icon
    screenshot-main.png # hero (existing assets/screenshot-main.png)
    settings-*.png      # user-provided setting-page screenshots
```

## Theme Tokens (from `FilmCanTheme.swift`)

| Token | Value |
|-------|-------|
| Background | `#1B1B1B` |
| Sidebar | `#1F1F1F` |
| Panel / card | `#2A2A2A` |
| Text (cream) | `#F4F2EE` |
| Accent (Kodak yellow) | `#FFC900` |
| Success (green) | `#3B9953` |
| Error (red) | `#E45141` |
| Card stroke | `rgba(244,242,238,.18)` / strong `.30` |
| Font | Space Grotesk (700/600/500/400) |

## Page Structure (single scroll)

1. **Sticky nav** — film-can logo + "FilmCan" wordmark; section anchor links
   (How it works · Features · FAQ · Support); yellow Download button.
   Reserve a **Docs** nav slot, commented out / hidden until phase 2.
2. **Hero** — badge "Free · GPL-3.0 · macOS 13+"; headline with yellow accent;
   one-line lead; dual CTA (Download for macOS / View on GitHub); version meta line;
   framed hero screenshot.
3. **How it works** — 4 numbered step cards (from `docs/quickstart.md`):
   Add sources → Add destinations → Run → Verify.
4. **Features** — 6-card grid (from CLAUDE.md): Fan-out copy, xxHash128 verify,
   Stop & resume, Netflix Ingest, Organization presets, Local & private.
5. **Download** — highlighted block: direct DMG button (current version) +
   "All releases / older versions" ghost button; macOS requirement note.
6. **Q&A** — accordion cards (from `docs/faq.md`): is it free, camera support,
   uploads, stop/resume (+ a few more from faq.md).
7. **Contact & Donate** — two boxes. Contact: `mailto:qtld@pm.me`,
   GitHub `qtld88/FilmCan`, "report a bug" link. Donate: GitHub Sponsors
   (`github.com/sponsors/qtld88`), Ko-fi (`ko-fi.com/filmcan`).
8. **Footer** — © 2026 FilmCan · GPL-3.0; Privacy / GitHub / Email links.

## Download Wiring (version automation)

- `version.json` holds `{ version, tag, dmg }`.
- `main.js` fetches it on load and fills:
  - primary button href:
    `https://github.com/qtld88/FilmCan/releases/download/<tag>/<dmg>`
  - button label and the hero/download version meta text.
  - ghost button href: `https://github.com/qtld88/FilmCan/releases`.
- `scripts/package_release.sh` gains a step that writes `website/version.json`
  from the version/tag/DMG it already produces, so the site updates on each release.
  Fallback: if `version.json` fetch fails, buttons default to the `/releases` page.

## Links (canonical)

- Email: `mailto:qtld@pm.me`
- GitHub: `https://github.com/qtld88/FilmCan`
- Releases: `https://github.com/qtld88/FilmCan/releases`
- Sponsors: `https://github.com/sponsors/qtld88`
- Ko-fi: `https://ko-fi.com/filmcan`

## Assets

- **Have:** `assets/screenshot-main.png` (hero), 1024 app icon in xcassets.
- **Generate (sips):** favicon, apple-touch-icon, og-image from the 1024 icon.
- **User provides:** one screenshot per setting page → placed in features / how-it-works.

## Responsive & Accessibility

- Grids (steps, features, contact/donate) collapse to 1 column under ~720px.
- Sticky nav collapses links to a compact menu on small screens.
- Honor `prefers-reduced-motion` (disable smooth-scroll / transitions).
- Semantic headings, descriptive alt text, AA contrast (cream on `#1B1B1B`,
  `#1B1B1B` text on yellow buttons).

## Phase 2 — Wiki (documented, not built)

A `/docs` section on the same Pages site, generated from existing `docs/*.md`,
reusing the V1 theme/CSS. The reserved Docs nav slot activates then. Each doc page
shares the header, footer, and theme tokens. Tooling choice (e.g. a minimal static
markdown renderer) deferred to the phase-2 spec.

## Acceptance Criteria

- `website/index.html` renders all 8 sections with the Kodak theme.
- Download button points to the current release DMG via `version.json`; ghost
  button points to `/releases`.
- FAQ accordion expands/collapses; nav anchors smooth-scroll.
- Email, GitHub, Sponsors, Ko-fi links resolve to the canonical URLs above.
- Layout is usable on mobile (single-column) and desktop.
- `package_release.sh` writes `website/version.json` on release.
- GitHub Actions workflow deploys `website/` to Pages on push to `main`.
