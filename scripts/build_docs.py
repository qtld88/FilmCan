#!/usr/bin/env python3
"""Render the curated docs allowlist to themed HTML under website/docs/.

Run from anywhere; paths are resolved relative to the repo root.
Exits non-zero on a missing source file, a link to a non-published page,
or a stray em dash in rendered output.
"""
import os
import re
import shutil
import sys
from pathlib import Path

import markdown

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
OUT = ROOT / "website" / "docs"

# (source path relative to docs/, sidebar group or None for the home page, nav title)
PAGES = [
    ("index.md", None, "Overview"),
    ("quickstart.md", "Getting started", "Quick Start"),
    ("installation.md", "Getting started", "Installation"),
    ("features/index.md", "Features", "Features Overview"),
    ("features/multi-destination.md", "Features", "Multi-Destination"),
    ("features/source-selection.md", "Features", "Source Selection"),
    ("features/destination-presets.md", "Features", "Destination Presets"),
    ("features/hash-lists.md", "Features", "Hash Lists"),
    ("features/safe-checks.md", "Features", "Safe Checks"),
    ("features/stop.md", "Features", "Stop & Resume"),
    ("features/transfer-history.md", "Features", "Transfer History"),
    ("features/push-notifications.md", "Features", "Push Notifications"),
    ("features/smart-date.md", "Features", "Smart Date"),
    ("features/visualizations.md", "Features", "Visualizations"),
    ("features/options.md", "Features", "Options"),
    ("features/netflix-ingest.md", "Features", "Netflix Ingest"),
    ("features/copy-engines.md", "Features", "Copy Engine"),
    ("reference/transfer-errors.md", "Reference", "Transfer Errors"),
    ("troubleshooting.md", "Help", "Troubleshooting"),
    ("faq.md", "Help", "FAQ"),
    ("privacy.md", "About", "Privacy"),
    ("ai-usage.md", "About", "AI Usage"),
    ("roadmap.md", "About", "Roadmap"),
]

ALLOWED = {src for src, _, _ in PAGES}
GROUP_ORDER = ["Getting started", "Features", "Reference", "Help", "About"]
TITLES = {src: title for src, _, title in PAGES}

errors = []


def out_path(src):
    return src[:-3] + ".html"  # features/stop.md -> features/stop.html


def rewrite_links(html, src):
    base = os.path.dirname(src)

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
                errors.append(f"{src}: links to non-published page: {m.group(1)}")
                return m.group(0)
            return f'href="/docs/{out_path(target)}{frag}"'
        return m.group(0)

    return re.sub(r'href="([^"]+)"', repl, html)


def sidebar(active_src):
    rows = ['<a class="home%s" href="/docs/">Documentation</a>'
            % (" active" if active_src == "index.md" else "")]
    for group in GROUP_ORDER:
        items = [(s, t) for (s, g, t) in PAGES if g == group]
        if not items:
            continue
        rows.append(f'<div class="grp"><span class="grp-t">{group}</span><ul>')
        for s, t in items:
            cls = ' class="active"' if s == active_src else ""
            rows.append(f'<li><a href="/docs/{out_path(s)}"{cls}>{t}</a></li>')
        rows.append("</ul></div>")
    return "\n".join(rows)


NAV = """<nav><div class="wrap">
  <a class="brand" href="/" style="text-decoration:none"><img src="/assets/icon.png" alt="FilmCan icon">FilmCan</a>
  <div class="links">
    <a href="/#how">How it works</a>
    <a href="/#features">Features</a>
    <a href="/docs/" class="active">Docs</a>
    <a href="/#faq">FAQ</a>
    <a href="/#support">Support</a>
    <a class="btn" href="/#download">Download</a>
  </div>
</div></nav>"""

TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · FilmCan Docs</title>
<link rel="icon" href="/assets/favicon.png">
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


def build():
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    for src, _, _ in PAGES:
        sp = DOCS / src
        if not sp.exists():
            errors.append(f"missing source: docs/{src}")
            continue
        md = markdown.Markdown(extensions=["tables", "fenced_code", "toc", "sane_lists"])
        body = md.convert(sp.read_text(encoding="utf-8"))
        body = rewrite_links(body, src)
        if "—" in body:
            errors.append(f"{src}: rendered HTML still contains an em dash")
        html = TEMPLATE.format(title=TITLES[src], nav=NAV, sidebar=sidebar(src), body=body)
        dest = OUT / out_path(src)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(html, encoding="utf-8")
    if errors:
        print("BUILD FAILED:", file=sys.stderr)
        for e in errors:
            print("  -", e, file=sys.stderr)
        sys.exit(1)
    print(f"built {len(PAGES)} docs pages into {OUT}")


if __name__ == "__main__":
    build()
