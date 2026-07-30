#!/usr/bin/env node
// gates/freeze/render_htmx.mjs — render every GET route of an htmx producer at
// every DERIVED width, asserting the console/page-error count is EXACT.
//
// This is the htmx-producer render half of the freeze gate (plan 04, the
// producer-shape seam surfaced by dogfood P14 finding #1). The stacked_kit
// producer keeps its Python/uv render inside freeze.sh unchanged.
//
// The producer is already being served by the designer's Node prototype server
// (serve.mjs, loopback, OS-assigned port) — the bash caller reads its ready line
// and passes the base URL here. Rendering a Jinja/htmx view means executing the
// designer runtime, so the page must come from the server, not the filesystem.
//
// Widths come ONLY from config (R3), derived from --targets (6.4); the caller
// resolves the derived viewport list and passes it as JSON. There are no width
// literals here.
//
// 4.3 (exact count) is preserved STRUCTURALLY: a FRESH page per (route, width,
// locale), with the console/pageerror handler bound to that page only — handlers
// can never accumulate across routes, so each error is reported exactly once.
//
// Playwright is imported from the designer runtime's node_modules via
// createRequire, so this gate's only Node dependency is the runtime itself (P09:
// the designer legitimately requires Node, so a dev-time gate MAY use it).
//
// args: <design-dir> <base-url> <evidence-dir> <viewports-json> <runtime-dir> [locales-csv]
//   viewports-json: [{"name","width","height"}, ...]  (the derived set, config order)
//   locales-csv:    "en,pl" — when the design carries l10n/, each route renders
//                   once per locale, the locale passed as ?lang=<locale> on the
//                   route URL and stamped on the screenshot name. Empty/absent
//                   = single render with no ?lang (a pre-i18n design).
// exit: 0 clean / 1 a route errored / 2 bad args
import { createRequire } from 'node:module';
import path from 'node:path';
import fs from 'node:fs';

const [designDir, baseUrl, evidenceDir, viewportsJson, runtimeDir, localesCsv] = process.argv.slice(2);
if (!designDir || !baseUrl || !viewportsJson || !runtimeDir) {
  console.error('usage: render_htmx.mjs <design-dir> <base-url> <evidence-dir> <viewports-json> <runtime-dir> [locales-csv]');
  process.exit(2);
}
// [null] = the no-l10n single render (no ?lang appended).
const locales = (localesCsv || '').split(',').filter(Boolean);
const langs = locales.length ? locales : [null];
const viewports = JSON.parse(viewportsJson);
if (!viewports.length) {
  console.error('FAIL: render: derived viewports matched no config viewport');
  process.exit(1);
}
const base = baseUrl.replace(/\/$/, '');

// Playwright lives in the designer runtime's node_modules; resolve it as if from
// serve.mjs (the runtime's own entry point).
const require = createRequire(path.join(runtimeDir, 'serve.mjs'));
const { chromium } = require('playwright');

// Enumerate GET routes from app.routes.js — a literal array of [METHOD, path, h].
// Matched by text regex so producer code is never executed here (the server does
// that). POSTs and the export are ignored.
const routesTxt = fs.readFileSync(path.join(designDir, 'app.routes.js'), 'utf8');
const routes = [...routesTxt.matchAll(/\[\s*['"]GET['"]\s*,\s*['"]([^'"]+)['"]/g)].map((m) => m[1]);
if (!routes.length) {
  console.error('FAIL: render: no GET routes found in app.routes.js');
  process.exit(1);
}

fs.mkdirSync(evidenceDir, { recursive: true });
const browser = await chromium.launch();
const errors = [];
for (const { name: vname, width, height } of viewports) {
  for (const route of routes) {
    for (const lang of langs) {
      // Fresh page per (route, width, locale) — 4.3: handlers cannot accumulate.
      const page = await browser.newPage({ viewport: { width, height } });
      const msgs = [];
      page.on('console', (m) => { if (m.type() === 'error') msgs.push(m.text()); });
      page.on('pageerror', (e) => msgs.push(String(e)));
      const url = base + route + (lang ? `${route.includes('?') ? '&' : '?'}lang=${encodeURIComponent(lang)}` : '');
      await page.goto(url, { waitUntil: 'load' });
      await page.waitForTimeout(1200);
      const slug = route === '/' ? 'root' : route.replace(/^\//, '').replace(/\//g, '__');
      const shot = lang ? `${slug}_${vname}_${lang}.png` : `${slug}_${vname}.png`;
      await page.screenshot({ path: path.join(evidenceDir, shot), fullPage: true });
      for (const m of msgs) errors.push(`${route}@${vname}${lang ? ` (${lang})` : ''}: ${m}`);
      await page.close();
      console.log(`  \u2713 render: ${route} @ ${vname} (${width}x${height})${lang ? ` [${lang}]` : ''} loaded`);
    }
  }
}
await browser.close();
for (const e of errors) console.log(`FAIL: render: console/page error — ${e}`);
console.log(`  render: ${routes.length * viewports.length * langs.length} route/viewport render(s) across ${viewports.length} derived width(s)${locales.length ? ` × ${locales.length} locale(s) [${locales.join(',')}]` : ''}, ${errors.length} error(s)`);
process.exit(errors.length ? 1 : 0);
