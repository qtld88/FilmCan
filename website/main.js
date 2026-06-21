// Single-open FAQ accordion using <details>
document.querySelectorAll('.qa').forEach((d) => {
  d.addEventListener('toggle', () => {
    if (d.open) {
      document.querySelectorAll('.qa[open]').forEach((o) => { if (o !== d) o.open = false; });
    }
  });
});

// Populate download links from version.json
const REPO = 'https://github.com/qtld88/FilmCan';
fetch('version.json')
  .then((r) => (r.ok ? r.json() : Promise.reject()))
  .then(({ version, tag, dmg }) => {
    const dmgUrl = `${REPO}/releases/download/${tag}/${dmg}`;
    const main = document.getElementById('dl-main');
    const hero = document.getElementById('dl-hero');
    if (main) { main.href = dmgUrl; main.textContent = `⬇ Download ${version} (.dmg)`; }
    if (hero) { hero.href = dmgUrl; }
    const md = document.getElementById('meta-download');
    const mh = document.getElementById('meta-hero');
    if (md) md.textContent = `FilmCan ${version} · universal · requires macOS 13 Ventura or later`;
    if (mh) mh.textContent = `FilmCan ${version} · universal · macOS 13 Ventura or later`;
  })
  .catch(() => { /* fallback: buttons already point at /releases */ });
