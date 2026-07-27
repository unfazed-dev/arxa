// Fixture htmx producer — a dependency-free stand-in for design/new-htmx/.
//
// emit_htmx's --self-test must run offline and with no `npm install`, so this
// server implements the SAME contract the real tree exposes (the contract
// emit_htmx actually depends on) using only node builtins:
//
//   * honours $PORT and prints a ready line containing http://localhost:<port>
//   * GET /?role=<role>&screen=<id> renders the stage: a .phone-screen root
//     carrying data-screen-label="<role> · <id>", wrapped in chrome that the
//     exclusions must strip (.dyn-island / .statusbar / .home-ind) and nested
//     inside .phone (outside the extraction root by construction)
//   * serves /assets/css/*.css and /assets/icon.svg
//   * renders the Phase-E placeholder when a role may not see a screen
//
// Deliberate calibration hooks:
//   * every page prints Date.now() into .fx-clock — with the frozen_clock
//     preload the two self-test runs agree and the second reports `unchanged`;
//     WITHOUT it the value moves and the write-on-diff check fails. The
//     self-test therefore calibrates the freeze itself, not just the diff.
//   * FIXTURE_PLACEHOLDER=1 forces the placeholder for fixture.two, so the
//     self-test can prove emit FAILS rather than freezing a placeholder as if
//     it were a real surface (the sweep's trap 2).
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

const ROOT = new URL('.', import.meta.url).pathname;
const PORT = Number(process.env.PORT || 4173);
const FORCE_PLACEHOLDER = process.env.FIXTURE_PLACEHOLDER === '1';

const MIME = { '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml' };

const SCREENS = {
  'fixture.one': { label: 'Fixture Home', body: '<h1 class="fx-title">Fixture Home</h1>' },
  'fixture.two': { label: 'Fixture Detail', body: '<h1 class="fx-title">Fixture Detail</h1>' },
  'fixture.hidden': { label: 'Fixture Hidden', body: '<h1 class="fx-title">Fixture Hidden</h1>' },
};

const page = (role, id) => {
  const screen = SCREENS[id];
  const placeholder = !screen || (FORCE_PLACEHOLDER && id === 'fixture.two');
  const inner = placeholder
    ? '<div class="st-sub">Phase E surface — not yet built.</div>'
    : `${screen.body}
        <p class="fx-copy">Rendered by the emit_htmx fixture producer.</p>
        <img class="fx-img" src="/assets/icon.svg" alt="icon" width="16" height="16">
        <div class="fx-styled" style="background-image: url(/assets/icon.svg)"></div>
        <span class="fx-clock">${Date.now()}</span>`;
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Fixture · ${id}</title>
<link rel="stylesheet" href="/assets/css/fonts.css">
<link rel="stylesheet" href="/assets/css/tokens.css">
<link rel="stylesheet" href="/assets/css/app.css">
<link rel="stylesheet" href="/assets/css/hda.css">
</head>
<body>
<div class="stage">
  <nav id="toolbar" class="toolbar">fixture toolbar chrome</nav>
  <div class="phone-wrap">
    <div class="phone">
      <div class="phone-band">
        <div class="phone-screen" data-theme="light" data-screen-label="${role} · ${id}">
          <div class="dyn-island"></div>
          <div class="statusbar"><span class="num">9:41</span></div>
          <div class="fx-content">${inner}</div>
          <div class="home-ind"></div>
        </div>
      </div>
    </div>
  </div>
</div>
</body>
</html>`;
};

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  if (url.pathname.startsWith('/assets/')) {
    try {
      const ext = url.pathname.slice(url.pathname.lastIndexOf('.'));
      const buf = await readFile(join(ROOT, url.pathname.replace(/^\//, '')));
      res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
      res.end(buf);
      return;
    } catch {
      res.writeHead(404).end('not found');
      return;
    }
  }
  if (url.pathname !== '/') {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end(`404 — no route for ${req.method} ${url.pathname}`);
    return;
  }
  const q = url.searchParams;
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(page(q.get('role') || 'felix', q.get('screen') || 'fixture.one'));
});

server.listen(PORT, () => {
  process.stdout.write(`fixture htmx design tree — http://localhost:${PORT}\n`);
});
