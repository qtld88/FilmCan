#!/usr/bin/env python3
"""Render the curated docs allowlist + homepage to themed, localized HTML.

Docs pages: docs/*.md, each split into <!-- lang:X --> sections, one section
per locale rendered through the markdown library.
Homepage: website-src/index.template.html with {{key}} placeholders, filled
from website-src/i18n/<locale>.json.

Run from anywhere; paths are resolved relative to the repo root.
Exits non-zero on: missing source file, link to a non-published page,
missing translation section/key, or a stray em dash in rendered output.
"""
import json
import os
import re
import shutil
import sys
from pathlib import Path

import markdown

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
SITE_SRC = ROOT / "website-src"
OUT = ROOT / "website"
DOCS_OUT = OUT / "docs"

LOCALES = ["en", "fr", "de", "es"]
DEFAULT_LOCALE = "en"

# (source path relative to docs/, sidebar group key or None for the home page)
PAGES = [
    ("index.md", None),
    ("quickstart.md", "getting-started"),
    ("installation.md", "getting-started"),
    ("features/index.md", "features"),
    ("features/multi-destination.md", "features"),
    ("features/source-selection.md", "features"),
    ("features/destination-presets.md", "features"),
    ("features/hash-lists.md", "features"),
    ("features/safe-checks.md", "features"),
    ("features/stop.md", "features"),
    ("features/transfer-history.md", "features"),
    ("features/push-notifications.md", "features"),
    ("features/smart-date.md", "features"),
    ("features/visualizations.md", "features"),
    ("features/options.md", "features"),
    ("features/netflix-ingest.md", "features"),
    ("features/copy-engines.md", "features"),
    ("reference/transfer-errors.md", "reference"),
    ("troubleshooting.md", "help"),
    ("faq.md", "help"),
    ("privacy.md", "about"),
    ("ai-usage.md", "about"),
    ("roadmap.md", "about"),
]

ALLOWED = {src for src, _ in PAGES}
GROUP_ORDER = ["getting-started", "features", "reference", "help", "about"]
GROUP_LABELS = {
    "getting-started": {"en": "Getting started", "fr": "Premiers pas", "de": "Erste Schritte", "es": "Primeros pasos"},
    "features": {"en": "Features", "fr": "Fonctionnalités", "de": "Funktionen", "es": "Funciones"},
    "reference": {"en": "Reference", "fr": "Référence", "de": "Referenz", "es": "Referencia"},
    "help": {"en": "Help", "fr": "Aide", "de": "Hilfe", "es": "Ayuda"},
    "about": {"en": "About", "fr": "À propos", "de": "Über", "es": "Acerca de"},
}
HOME_LABEL = {"en": "Documentation", "fr": "Documentation", "de": "Dokumentation", "es": "Documentación"}

errors = []


def locale_root(loc):
    return "/" if loc == DEFAULT_LOCALE else f"/{loc}/"


def out_path(src):
    return src[:-3] + ".html"  # features/stop.md -> features/stop.html


def load_strings():
    strings = {}
    for loc in LOCALES:
        path = SITE_SRC / "i18n" / f"{loc}.json"
        if not path.exists():
            errors.append(f"missing i18n file: website-src/i18n/{loc}.json")
            strings[loc] = {}
            continue
        strings[loc] = json.loads(path.read_text(encoding="utf-8"))
    base_keys = set(strings.get(DEFAULT_LOCALE, {}).keys())
    for loc in LOCALES:
        if loc == DEFAULT_LOCALE:
            continue
        missing = base_keys - set(strings.get(loc, {}).keys())
        if missing:
            errors.append(f"website-src/i18n/{loc}.json missing keys: {sorted(missing)}")
    return strings


def split_sections(text, src):
    parts = re.split(r"^<!--\s*lang:(\w+)\s*-->\s*$", text, flags=re.M)
    sections = {}
    for i in range(1, len(parts), 2):
        sections[parts[i]] = parts[i + 1].strip("\n")
    for loc in LOCALES:
        if loc not in sections:
            errors.append(f"{src}: missing <!-- lang:{loc} --> section")
    return sections


def rewrite_links(html, src, loc):
    base = os.path.dirname(src)
    root = locale_root(loc)

    def repl(m):
        href = m.group(1)
        if re.match(r"^(https?:|mailto:|#|/)", href):
            return m.group(0)
        frag = ""
        if "#" in href:
            href, frag = href.split("#", 1)
            frag = "#" + frag
        if href.endswith(".md"):
            target = os.path.normpath(os.path.join(base, href)).replace(os.sep, "/")
            if target not in ALLOWED:
                errors.append(f"{src} ({loc}): links to non-published page: {m.group(1)}")
                return m.group(0)
            return f'href="{root}docs/{out_path(target)}{frag}"'
        return m.group(0)

    return re.sub(r'href="([^"]+)"', repl, html)


def switcher(src, loc):
    labels = {"en": "EN", "fr": "FR", "de": "DE", "es": "ES"}
    slug = f"docs/{out_path(src)}" if src else ""
    items = []
    for l in LOCALES:
        href = f"{locale_root(l)}{slug}" if slug else locale_root(l)
        cls = ' class="active"' if l == loc else ""
        items.append(f'<a{cls} href="{href}">{labels[l]}</a>')
    return '<div class="lang-switch">' + " · ".join(items) + "</div>"


def hreflang_tags(src):
    slug = f"docs/{out_path(src)}" if src else ""
    tags = []
    for l in LOCALES:
        href = f"{locale_root(l)}{slug}" if slug else locale_root(l)
        tags.append(f'<link rel="alternate" hreflang="{l}" href="https://www.filmcan.eu{href}">')
    default_href = f"/{slug}" if slug else "/"
    tags.append(f'<link rel="alternate" hreflang="x-default" href="https://www.filmcan.eu{default_href}">')
    return "\n".join(tags)


def nav(loc, strings, in_docs, src=None):
    s = strings.get(loc, {})
    root = locale_root(loc)
    docs_active = ' class="active"' if in_docs else ""
    return f"""<nav><div class="wrap">
  <a class="brand" href="{root}" style="text-decoration:none"><img src="/assets/icon.png" alt="FilmCan icon">FilmCan</a>
  <div class="links">
    <a href="{root}#how">{s.get('nav.how', 'How it works')}</a>
    <a href="{root}#features">{s.get('nav.features', 'Features')}</a>
    <a href="{root}docs/"{docs_active}>{s.get('nav.docs', 'Docs')}</a>
    <a href="{root}#faq">{s.get('nav.faq', 'FAQ')}</a>
    <a href="{root}#support">{s.get('nav.support', 'Support')}</a>
    <a class="btn" href="{root}#download">{s.get('nav.download', 'Download')}</a>
    {switcher(src, loc)}
  </div>
</div></nav>"""


def sidebar(active_src, loc, page_titles):
    root = locale_root(loc)
    rows = ['<a class="home%s" href="%sdocs/">%s</a>'
            % (" active" if active_src == "index.md" else "", root, HOME_LABEL[loc])]
    for group in GROUP_ORDER:
        items = [s for (s, g) in PAGES if g == group]
        if not items:
            continue
        rows.append(f'<div class="grp"><span class="grp-t">{GROUP_LABELS[group][loc]}</span><ul>')
        for s in items:
            cls = ' class="active"' if s == active_src else ""
            rows.append(f'<li><a href="{root}docs/{out_path(s)}"{cls}>{page_titles[s]}</a></li>')
        rows.append("</ul></div>")
    return "\n".join(rows)


DOC_TEMPLATE = """<!DOCTYPE html>
<html lang="{loc}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · FilmCan Docs</title>
<link rel="icon" href="/assets/favicon.png">
{hreflang}
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/styles.css">
<link rel="stylesheet" href="/docs.css">
</head>
<body class="docs">
{nav}
<div class="docs-wrap">
  <input type="checkbox" id="sb-toggle" hidden>
  <label for="sb-toggle" class="sb-btn">Menu</label>
  <aside class="sidebar">{sidebar}</aside>
  <main class="doc">{body}</main>
</div>
</body>
</html>
"""


def first_h1_title(md_text, fallback):
    m = re.search(r"^#\s+(.+)$", md_text, flags=re.M)
    return m.group(1).strip() if m else fallback


def build_docs(strings):
    if DOCS_OUT.exists():
        shutil.rmtree(DOCS_OUT)
    DOCS_OUT.mkdir(parents=True)

    raw_sections = {}
    titles = {loc: {} for loc in LOCALES}
    for src, _ in PAGES:
        sp = DOCS / src
        if not sp.exists():
            errors.append(f"missing source: docs/{src}")
            continue
        sections = split_sections(sp.read_text(encoding="utf-8"), src)
        raw_sections[src] = sections
        for loc in LOCALES:
            titles[loc][src] = first_h1_title(sections.get(loc, ""), src)

    count = 0
    for loc in LOCALES:
        for src, _ in PAGES:
            if src not in raw_sections:
                continue
            body_md = raw_sections[src].get(loc, "")
            md = markdown.Markdown(extensions=["tables", "fenced_code", "toc", "sane_lists"])
            body = md.convert(body_md)
            body = rewrite_links(body, src, loc)
            if "—" in body:
                errors.append(f"{src} ({loc}): rendered HTML still contains an em dash")
            html = DOC_TEMPLATE.format(
                loc=loc,
                title=titles[loc][src],
                hreflang=hreflang_tags(src),
                nav=nav(loc, strings, in_docs=True, src=src),
                sidebar=sidebar(src, loc, titles[loc]),
                body=body,
            )
            dest_dir = DOCS_OUT if loc == DEFAULT_LOCALE else OUT / loc / "docs"
            dest = dest_dir / out_path(src)
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(html, encoding="utf-8")
            count += 1
    print(f"built {count} docs pages")


def build_homepage(strings):
    template_path = SITE_SRC / "index.template.html"
    if not template_path.exists():
        errors.append("missing website-src/index.template.html")
        return
    template = template_path.read_text(encoding="utf-8")
    for loc in LOCALES:
        html = template
        for key, value in strings.get(loc, {}).items():
            html = html.replace("{{" + key + "}}", value)
        html = html.replace("{{HREFLANG}}", hreflang_tags(None))
        html = html.replace("{{NAV}}", nav(loc, strings, in_docs=False, src=None))
        leftover = re.findall(r"\{\{[a-zA-Z0-9_.]+\}\}", html)
        if leftover:
            errors.append(f"index.html ({loc}): unresolved placeholders: {sorted(set(leftover))}")
        if "—" in html:
            errors.append(f"index.html ({loc}): rendered HTML still contains an em dash")
        dest_dir = OUT if loc == DEFAULT_LOCALE else OUT / loc
        dest_dir.mkdir(parents=True, exist_ok=True)
        (dest_dir / "index.html").write_text(html, encoding="utf-8")
    print(f"built {len(LOCALES)} homepage variants")


def build():
    strings = load_strings()
    build_docs(strings)
    build_homepage(strings)
    if errors:
        print("BUILD FAILED:", file=sys.stderr)
        for e in errors:
            print("  -", e, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    build()
