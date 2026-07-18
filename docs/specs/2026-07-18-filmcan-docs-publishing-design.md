# FilmCan Docs Publishing — Design

Date: 2026-07-18
Status: Approved (pending spec review)

## Goal

Publish a curated subset of `docs/` as styled HTML pages on the FilmCan
website (`www.filmcan.eu`), consistent with the Kodak theme, with real URLs,
built at deploy time from the existing markdown. Fills the reserved "Docs"
nav slot (previously deferred to phase 2).

## Non-goals

- No client-side markdown rendering, no third-party docs generator (MkDocs,
  Docusaurus). The hand-written static site stays hand-written.
- No editing of the canonical `docs/*.md` content model beyond the targeted
  cleanups listed below. Docs remain authored as markdown in `docs/`.
- No search, no versioned docs, no dark/light toggle work beyond what the
  existing site theme already provides.

## Approach

A small build script converts the curated markdown files to themed HTML.
It runs locally (for preview) and in GitHub Actions before the Pages
artifact is uploaded. Generated HTML lands in `website/docs/` and is never
committed (gitignored), so there is no source/output drift.

## Content: include / exclude

### Include (~21 pages), grouped for the docs sidebar

- **Getting started**: `quickstart.md`, `installation.md`
- **Features**: `features/index.md`, `features/multi-destination.md`,
  `features/source-selection.md`, `features/destination-presets.md`,
  `features/hash-lists.md`, `features/safe-checks.md`, `features/stop.md`,
  `features/transfer-history.md`, `features/push-notifications.md`,
  `features/smart-date.md`, `features/visualizations.md`,
  `features/options.md`, `features/netflix-ingest.md`,
  `features/copy-engines.md`
- **Reference**: `reference/transfer-errors.md`
- **Help**: `troubleshooting.md`, `faq.md`
- **About**: `privacy.md`, `ai-usage.md`, `roadmap.md`

The docs home at `/docs/` is rendered from `docs/index.md`.

### Exclude

- Internal / dev: `architecture.md`, `technical-debt.md`, `qa.md`,
  `smoke-qa-checklist.md`, `contributing.md`
- rsync tombstone stubs: `features/rsync.md`, `features/custom-rsync.md`
- Internal gap analysis: `reference/netflix-asc-mhl-requirements.md`
- Duplicate of site Support section: `support.md`
- `ACKNOWLEDGEMENTS.md` (optional, low value; excluded for now)

The include set is defined as an explicit allowlist in the build script,
not an exclude filter, so new internal docs never leak onto the site by
default.

## Content cleanups (applied to canonical `docs/*.md`, committed)

1. **`features/copy-engines.md`**: remove the rsync history entirely (the
   deprecation blockquote and any rsync-vs-FilmCan-Engine comparison).
   Rewrite so it describes only the current single FilmCan Engine and its
   fast / paranoid verify modes. No mention of an engine picker.
2. **Broken internal links to excluded pages**: rewrite links that point to
   `features/rsync.md` or `features/custom-rsync.md` (e.g. in `index.md`,
   `features/index.md`) so they point to `features/copy-engines.md` or are
   removed. No published page may link to an unpublished page.
3. **Em dashes**: strip `—` from every published doc, per the project
   writing rule (replace with comma / colon / sentence split). This edits
   the canonical `.md` files, not just the generated HTML.

Cleanups to the source markdown are committed normally. Internal/excluded
docs are left as-is except where they would break a published link.

## Rendering & build

### Script: `scripts/build_docs.py`

- Python 3, uses the `markdown` library with extensions: `tables`,
  `fenced_code`, `toc`, `sane_lists`.
- Reads the explicit allowlist (path → sidebar group + title).
- For each entry: render markdown body to HTML, rewrite intra-doc links
  (`*.md` → `*.html`, dropping `./`), wrap in the page template, write to
  `website/docs/<mirrored-path>.html`.
- Mirrors the source tree: `docs/features/stop.md` →
  `website/docs/features/stop.html`. `docs/index.md` →
  `website/docs/index.html`.
- Idempotent: clears `website/docs/` at the start of each run.
- Fails loudly (non-zero exit) if an allowlisted source file is missing or
  if a rendered page contains a link to a `.md`/path outside the allowlist.

### Page template (Kodak theme)

- Same top `<nav>` as the main site (brand + section links + Download btn),
  with the Docs link marked active.
- Left sidebar: the grouped allowlist, current page highlighted.
- Content column: rendered markdown, max-width for readability.
- Shared stylesheet `website/docs.css` (imports the same CSS custom
  properties / font as `styles.css`; adds docs-only layout: sidebar grid,
  prose typography, code-block and table styling in Kodak colors).
- Responsive: sidebar collapses under a disclosure on narrow viewports;
  body never scrolls horizontally (code/tables scroll in their own box).

### URLs

Clean paths served by GitHub Pages: `/docs/`, `/docs/quickstart.html`,
`/docs/features/netflix-ingest.html`. (Pages serves the `.html` files
directly; no rewrite rules required. The nav link targets `/docs/`.)

## Site integration

- **Nav**: uncomment / add the reserved Docs slot in `website/index.html`:
  `<a href="docs/">Docs</a>`. The generated docs pages carry the same nav.
- **Deploy workflow** (`.github/workflows/deploy-pages.yml`): before
  `upload-pages-artifact`, add a step that sets up Python, runs
  `pip install markdown`, then `python scripts/build_docs.py`. The upload
  path stays `website` (now including generated `website/docs/`).
  Also add `docs/**` and `scripts/build_docs.py` to the workflow's `paths`
  trigger so doc edits redeploy.
- **`.gitignore`**: add `website/docs/` (build output).

## Testing / verification

- `scripts/build_docs.py` run locally produces `website/docs/` with one
  HTML file per allowlisted source and no others.
- Build fails if an allowlisted file is missing or a published page links to
  an unpublished target (link-integrity check).
- Local preview (python http.server on `website/`) renders `/docs/`, a
  feature page, the sidebar, and a code block / table correctly in the Kodak
  theme; nav Docs link works; mobile sidebar collapses.
- No `—` in any generated docs HTML.
- CI: the Pages deploy succeeds with the added build step and the live
  `/docs/` route loads.

## Acceptance criteria

- `www.filmcan.eu/docs/` and every allowlisted page load, themed, with a
  working sidebar and top nav.
- No excluded/internal/stale page is reachable from the site.
- No published page links to an unpublished page or to a `.md` file.
- Deploy remains a single push-to-main → Actions flow; no manual doc build.
- Source markdown edits (cleanups) are committed; generated HTML is not.
