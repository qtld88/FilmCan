# FilmCan Site & Docs Internationalization — Design

## Goal

Serve the marketing site (`website/index.html`) and the published docs (`website/docs/**`) in English, French, German, and Spanish. English stays at the site root (no URL break for existing links/SEO). Build-time rendering only, no client-side JS, matching the existing docs pipeline.

## Non-goals

- Localizing the FilmCan macOS app itself. The app UI is English-only; this project does not touch `FilmCan/Sources/`.
- Native-speaker review of the FR/DE/ES translations. Machine-quality translation is accepted for this pass (explicit user decision).
- Any language beyond EN/FR/DE/ES in this pass.

## URL scheme

```
www.filmcan.eu/              en (default, unchanged path)
www.filmcan.eu/fr/           fr
www.filmcan.eu/de/           de
www.filmcan.eu/es/           es
www.filmcan.eu/docs/...      en (unchanged path)
www.filmcan.eu/fr/docs/...   fr
www.filmcan.eu/de/docs/...   de
www.filmcan.eu/es/docs/...   es
```

Every page has the same slug across locales (`docs/quickstart.html` ↔ `fr/docs/quickstart.html`). This makes the language switcher a pure prefix swap computable by the build script — no client JS needed.

## Two content mechanisms (different content shapes need different formats)

### 1. Docs pages (`docs/*.md`) — single file, fenced language sections

Each of the 21 published markdown files gets 4 top-level sections, delimited by a marker on its own line:

```markdown
<!-- lang:en -->
# Quick Start
...English markdown...

<!-- lang:fr -->
# Démarrage rapide
...French markdown...

<!-- lang:de -->
# Schnellstart
...German markdown...

<!-- lang:es -->
# Inicio rápido
...Spanish markdown...
```

The build script splits the **raw text** on these markers before handing each chunk to the `markdown` library, so the markers never reach the Markdown parser (no risk of them being swallowed or mis-rendered). The page title for each locale comes from that locale's first `# H1`, not from a hardcoded title dict — this keeps the title translated without a second place to edit.

Rationale for "one file, four sections" over "four files": keeps a page's translations physically adjacent, so editing English and forgetting to touch the other three is visible in the same diff.

### 2. `website/index.html` — template + JSON strings (NOT fenced)

`index.html` is 65KB, almost entirely hand-authored inline SVG icon paths. Fencing the whole file per language would quadruple that to ~260KB of duplicated markup and risk a subagent mangling SVG path data while translating. Instead:

- The file moves to `website-src/index.template.html` — same structure, same SVGs, untouched — but every translatable string (headings, paragraphs, `alt` text, `<title>`, meta tags, button labels, FAQ entries, footer text) is replaced with a `{{key}}` placeholder.
- Four JSON files hold the actual copy: `website-src/i18n/en.json`, `fr.json`, `de.json`, `es.json`. Same keys in every file.
- The build script does plain `str.replace("{{key}}", value)` substitution once per locale, writing `website/index.html` (en), `website/fr/index.html`, `website/de/index.html`, `website/es/index.html`.

`website/index.html` becomes a **build output**, not a hand-edited file, exactly like `website/docs/**` already is. It moves from tracked to gitignored.

### 3. Shared site chrome (nav bar, docs sidebar group labels, language switcher, "Menu" toggle)

These short strings are used by both `index.html` and every docs page, so they live in the same `website-src/i18n/<lang>.json` files under a `nav.*` / `sidebar.*` namespace, avoiding a second place where nav wording could drift between the homepage and docs pages.

## Translation glossary (consistency across all four languages)

To keep terminology stable across ~21 docs pages × 3 languages, translated by separate subagent dispatches, fix these choices up front:

| English | Rule |
|---|---|
| **App UI labels** (`Options → Basic`, `Verification`, `Fast`, `Paranoid`, `Copy mode`, `Open Anyway`, menu/button names) | **Never translate.** The app itself is English-only. Docs must quote the exact on-screen string, in English, even inside FR/DE/ES prose, so a reader can match what they see. |
| backup / offload | Keep **"backup"** untranslated in FR/DE/ES — it's the loanword crews actually use on set in all three languages. Don't force "sauvegarde" / "Datensicherung" / "copia de seguridad". |
| roll (ASC MHL term, one card's folder) | Keep **"roll"** untranslated — it's the term the ASC MHL spec itself uses, and what crews say. |
| source / destination / drive | FR: source / destination / disque · DE: Quelle / Ziel / Laufwerk · ES: origen / destino / unidad |
| verify / verification | FR: vérifier / vérification · DE: verifizieren / Verifizierung · ES: verificar / verificación |
| resume | FR: reprendre / reprise · DE: fortsetzen · ES: reanudar |
| hash list | FR: liste de hachage · DE: Hash-Liste · ES: lista de hash |
| MHL / ASC MHL | Never translate — it's a named industry standard. |
| card (camera card) | FR: carte · DE: Karte · ES: tarjeta |

Every translation task below must apply this table. No em dashes in any language (existing project-wide rule, checked by the build script).

## Build script changes (`scripts/build_docs.py`)

- Loop over `LOCALES = ["en", "fr", "de", "es"]` for both docs pages and `index.html`.
- Docs: split source `.md` on `<!-- lang:X -->` markers, convert only the current locale's chunk, extract title from its first H1.
- `rewrite_links`: becomes locale-aware — a link inside the `fr` chunk resolves to `/fr/docs/...`, not `/docs/...`.
- Sidebar group labels come from a small `GROUP_LABELS` dict (5 groups × 4 languages, hardcoded in the script — too small to need JSON).
- Nav bar and language switcher are generated from `website-src/i18n/<lang>.json`'s `nav.*` keys, same template for every locale, docs and homepage.
- `index.html`: read `website-src/index.template.html` once, substitute `{{key}}` per locale from the JSON files, write to `website/index.html` (en) or `website/<locale>/index.html`.
- Em-dash check runs across every generated file in every locale (already exists for docs; extend to `index.html` outputs).
- Missing translation key (present in `en.json`, absent in another locale's JSON) is a build failure, loud, same pattern as the existing "missing source file" / "link to non-published page" checks.

## Directory layout after this change

```
website-src/                        NEW, committed (source of truth for index.html)
  index.template.html
  i18n/
    en.json
    fr.json
    de.json
    es.json

docs/*.md                           MODIFIED — each gets 4 lang: sections
docs/features/*.md                  MODIFIED — same

website/                            deploy artifact root (unchanged path)
  styles.css, docs.css, main.js, assets/   unchanged, hand-authored, not templated
  index.html                        GENERATED (en) — was hand-authored, now gitignored
  fr/index.html                     GENERATED
  de/index.html                     GENERATED
  es/index.html                     GENERATED
  docs/**                           GENERATED (en) — existing, unchanged pattern
  docs/fr/**                        GENERATED
  docs/de/**                        GENERATED
  docs/es/**                        GENERATED
```

`.gitignore` gains `website/index.html`, `website/fr/`, `website/de/`, `website/es/` (docs/ variants already covered by the existing `website/docs/` entry once it's read as a prefix — needs the explicit locale subpaths added since `website/docs/` doesn't match `website/fr/docs/`).

## Language switcher

Small text row in the nav, next to the existing links: `EN · FR · DE · ES`, current language not a link (or bold/inactive). Each link is a plain `<a href>` computed by the build script from the current page's locale-independent slug — same mechanism as the existing sidebar "active" class.

## SEO

Each generated page gets `<link rel="alternate" hreflang="X" href="...">` for all 4 locales plus `x-default` pointing at the English version, in `<head>`.

## Acceptance criteria

- `python scripts/build_docs.py` builds 4× the pages (84 docs pages + 4 homepage variants), zero em dashes anywhere, zero broken internal links, zero missing translation keys.
- Every generated page's language switcher links resolve (spot-check via local server).
- Docs page in any locale that links to another docs page stays within that same locale.
- App UI strings (button/menu names) inside FR/DE/ES docs prose are verbatim English, matching current `FilmCan/Sources/Views/*` labels where checkable.
- GitHub Actions workflow trigger paths updated to include `website-src/**`.
