// probe-flowwalk.mjs — the flow walk: tap a flow edge's element INSIDE a tile's
// iframe and watch the parent row's active tile advance, without the grid being
// rebuilt.
//
// This is the check the design selftest structurally cannot make. "every
// hx-target names an element that exists" and "every GET route answers 200"
// both pass just as happily on a toolbar with the wrong tools in it and on a
// walk that never moves — they are structural, not behavioural. The two things
// that actually matter here only exist at runtime, in a browser, across an
// iframe boundary:
//
//   1. the views lens does NOT offer an interactive mode (its destination would
//      come from nextEdge with no flow to scope it, i.e. a guess), and
//   2. a tap inside the walked tile moves the PARENT row, keeps the tile
//      showing the screen it is labelled with, and does not destroy the grid.
//
// Run against a live studio:
//   dart run appboxd/bin/appbox.dart design serve designs/appbox-studio --port 4319 --json --project portalo
//   node tools/probe-flowwalk.mjs
// Override with APPBOX_BASE / APPBOX_CHROME.
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { chromium } = await import(
  path.join(REPO, 'skills/appbox-designer/runtime/node_modules/playwright-core/index.mjs'));
const CHROME = process.env.APPBOX_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const BASE = process.env.APPBOX_BASE || 'http://localhost:4319';

const FLOW = 'flow-onboarding';
const FROM = 'portalo.auth';   // the screen with the Continue button
const TO = 'portalo.home';     // where flow-onboarding's "continue" edge points

let failures = 0;
const check = (label, ok, detail = '') => {
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? ' — ' + detail : ''}`);
  if (!ok) failures++;
};

let b;
try {
  b = await chromium.launch({ executablePath: CHROME, headless: true });
  const p = await b.newPage({ viewport: { width: 1600, height: 1000 } });
  const errs = [];
  const http4xx = [];
  p.on('pageerror', (e) => errs.push('page: ' + e.message));
  p.on('console', (m) => { if (m.type() === 'error') errs.push('console: ' + m.text().slice(0, 120)); });
  // Chrome's console line for a failed request names no URL, so a bare
  // "Failed to load resource: 404" is unactionable on its own — and the ONE we
  // expect (Chrome's own /favicon.ico fetch) never reaches CDP network events
  // at all, because the browser issues it rather than the renderer. So: name
  // every 4xx we CAN see here, and treat an unnamed console 404 as the favicon
  // (finding 18) rather than failing on it.
  p.on('response', (r) => { if (r.status() >= 400) http4xx.push(`http ${r.status()} ${r.url().replace(BASE, '')}`); });

  // ALWAYS start from /design, never from /design/viewer directly. The viewer
  // route returns a NAMED FRAGMENT (#viewerSwap), so navigating a browser to
  // it yields a bare fragment with no htmx global — and the flow-walk island
  // reaches the parent through `window.parent.htmx`. Driving the real UI is
  // also the only way this probe tests what a user actually does.
  console.log('\n=== A. views lens offers no interactive mode ===');
  await p.goto(`${BASE}/design`, { waitUntil: 'networkidle' });
  await p.waitForTimeout(900);
  const viewsTools = await p.$$eval('.dv-tile-tools a', (as) => as.map((a) => a.getAttribute('title') || ''));
  check('no walk control in views', !viewsTools.some((t) => /walk the flow/i.test(t)),
    `titles: ${[...new Set(viewsTools)].join(' | ') || '(none)'}`);
  check('no advance control in views', !viewsTools.some((t) => /^advance/i.test(t)));
  // The state must be clamped too, not just the control: a stale ?live= in the
  // URL used to paint an interactive, uncloseable tile in views. Driven through
  // the parent's own htmx so the page (and its htmx global) stay intact.
  await p.evaluate((u) => window.htmx.ajax('GET', u, { target: '#design-viewer', swap: 'morph:outerHTML' }),
    `/design/viewer?mode=views&flow=${FLOW}&step=${FROM}&live=${FROM}`);
  await p.waitForTimeout(900);
  check('stale walk params cannot arm a views tile',
    (await p.$$('.dv-tile.is-live')).length === 0);

  console.log('\n=== B. arm the walk on the flows lens ===');
  // Switch lens the way the mini panel does, then arm the walk from the tile's
  // own hover toolbar — the user's path, not a hand-built URL.
  await p.evaluate((u) => window.htmx.ajax('GET', u, { target: '#design-viewer', swap: 'morph:outerHTML' }),
    '/design/viewer?mode=flows');
  await p.waitForTimeout(900);
  const walkBtn = await p.$(`.dv-tile[data-id="${FROM}"] a[title*="Walk the flow"]`);
  check('flows lens offers the walk control', !!walkBtn);
  if (walkBtn) { await walkBtn.click({ force: true }); await p.waitForTimeout(1200); }
  const activeBefore = await p.$$eval('.dv-tile.is-live', (ts) => ts.map((t) => t.dataset.id));
  check('exactly one tile is the current step', activeBefore.length === 1, activeBefore.join(','));
  check(`the step is ${FROM}`, activeBefore[0] === FROM, String(activeBefore[0]));

  // Mark every iframe so grid destruction is detectable.
  await p.evaluate(`[...document.querySelectorAll('iframe')].forEach((f,i)=>f.__walk='w'+i)`);
  const framesBefore = await p.evaluate(`document.querySelectorAll('iframe').length`);

  console.log('\n=== C. tap Continue INSIDE the tile iframe ===');
  const fr = await p.$(`.dv-tile[data-id="${FROM}"] iframe`);
  const doc = await fr.contentFrame();
  const island = await doc.evaluate(`!!document.querySelector('script[src*="flowwalk.js"]')`);
  check('flow-walk island loaded in the walked tile', island);
  // The island reaches the row through window.parent.htmx. If the parent is a
  // bare fragment (or cross-origin) it bails silently, so assert the bridge
  // exists rather than inferring it from a passing end state.
  check('parent htmx bridge reachable from inside the tile',
    await doc.evaluate(`(()=>{try{return typeof window.parent.htmx==='object'}catch(e){return false}})()`));

  const target = await doc.$('[data-el="button:Continue"]');
  check('the edge element exists on the screen', !!target);

  if (target) {
    await target.click({ force: true });
    await p.waitForTimeout(1800);
  }

  console.log('\n=== D. the ROW advanced, the grid survived ===');
  const activeAfter = await p.$$eval('.dv-tile.is-live', (ts) => ts.map((t) => t.dataset.id));
  check(`active tile moved to ${TO}`, activeAfter.length === 1 && activeAfter[0] === TO,
    `now: ${activeAfter.join(',') || '(none)'}`);

  const kept = await p.evaluate(`[...document.querySelectorAll('iframe')].filter(f=>f.__walk!==undefined).length`);
  const framesAfter = await p.evaluate(`document.querySelectorAll('iframe').length`);
  check('iframes survived the advance (morph, not rebuild)', kept === framesBefore,
    `${kept}/${framesBefore} kept, ${framesAfter} present`);

  // The whole point of the walk: the tile keeps showing the screen it is
  // labelled with. If the in-frame navigation were not suppressed, the row
  // would show the destination screen twice.
  // Read the frame's LIVE url, not its src attribute: hx-boost swaps the
  // document in place, so a navigated frame keeps its original src and the
  // attribute check would pass on exactly the failure it is meant to catch.
  const stillThere = await p.$(`.dv-tile[data-id="${FROM}"] iframe`);
  const liveUrl = stillThere ? await (await stillThere.contentFrame())?.evaluate(() => location.pathname) : null;
  check(`${FROM} tile still shows its own screen (in-frame nav suppressed)`,
    !!liveUrl && liveUrl.includes(FROM), liveUrl || '(tile gone)');
  check('the source tile is no longer the active step',
    !activeAfter.includes(FROM));

  console.log('\n=== errors ===');
  const named4xx = http4xx.filter((e) => !/favicon/i.test(e));
  // Drop the unnamed console 404s that have no matching named 4xx: that is
  // Chrome's own favicon fetch (finding 18), cosmetic and not ours.
  const real = errs.filter((e) => {
    if (/page:/.test(e)) return true;
    if (/Failed to load resource/.test(e) && named4xx.length === 0) return false;
    return true;
  });
  for (const e of named4xx) console.log('  ! ' + e);
  console.log(real.length ? real.slice(0, 6).map((e) => '  ! ' + e).join('\n') : '  none');
  check('no page errors or unexplained 4xx', real.length === 0 && named4xx.length === 0);

  console.log(failures === 0 ? '\nALL CHECKS PASSED' : `\n${failures} CHECK(S) FAILED`);
  process.exitCode = failures === 0 ? 0 : 1;
} catch (e) {
  console.log('PROBE ERROR:', e.message);
  process.exitCode = 1;
} finally {
  if (b) await b.close();
}
