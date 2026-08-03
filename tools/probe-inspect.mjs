// probe-inspect.mjs — the inspector pane (activity panel, 4th view; D14-D17):
// arm, hover feeds the pane (unlocked), click locks it, a further hover while
// locked changes nothing ("locked wins"), the lock survives a full htmx morph
// of the panel (session state, not DOM state — D16), the pane's own unlock
// button drops the lock and falls back to the last hover, the pin button
// POSTs to chat context WITHOUT reloading the inspected iframe, and a hover
// while the inspector is not the active view is a no-op (204 guard — D14).
// Run against a live studio:
//   dart run appboxd/bin/appbox.dart design serve designs/appbox-studio --port 4319 --json --project portalo
//   node tools/probe-inspect.mjs
// Override with APPBOX_BASE / APPBOX_CHROME.
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { chromium } = await import(
  path.join(REPO, 'skills/appbox-designer/runtime/node_modules/playwright-core/index.mjs'));
const CHROME = process.env.APPBOX_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
import { resolveBase, requireDisposableProject, waitFor, waitQuiet, trackTransitions } from './_probe_base.mjs';
const BASE = resolveBase();
// This probe locks/pins/unlocks the inspector and POSTs into chat context —
// mutates whatever project BASE is serving. See _probe_base.mjs for why
// this can't just trust --project and what "disposable" means here.
await requireDisposableProject(BASE);
// Every call site below reads the DOM immediately after. A flat 700ms was a
// guess measured on an idle machine; under load the read landed mid-swap and
// the probe reported regressions that were not there (#48/#50). Waiting for the
// page to stop changing is correct in both directions: faster when idle, and
// still correct when the machine is busy.
const s = (p) => waitQuiet(p);
let b, fails = 0;
const check = (n, ok, x = '') => { if (!ok) fails++; console.log(`  [${ok ? 'PASS' : 'FAIL'}] ${n}${x ? ' — ' + x : ''}`); };

try {
  b = await chromium.launch({ executablePath: CHROME, headless: true });
  const p = await b.newPage({ viewport: { width: 1600, height: 1000 } });
  await trackTransitions(p);
  const reqs = []; p.on('request', (r) => { if (/inspector\/(select|unlock)|context\/element/.test(r.url())) reqs.push(r.method() + ' ' + r.url().replace(BASE, '')); });
  const errs = []; p.on('pageerror', (e) => errs.push('page: ' + e.message));
  p.on('console', (m) => { if (m.type() === 'error') errs.push('console: ' + m.text().slice(0, 120)); });
  p.on('response', (r) => { if (r.status() >= 400) errs.push(`http ${r.status()} ${r.url().replace(BASE, '')}`); });

  await p.goto(BASE + '/design', { waitUntil: 'networkidle' }); await s(p);

  console.log('=== 1. switch the activity panel to the inspector view ===');
  await p.click('a.panel-views-icon[href="/design/inspector"]'); await s(p);
  check('carousel icon is active', await p.$eval('a.panel-views-icon[href="/design/inspector"]', (e) => e.classList.contains('is-active')));
  check('#av-list is rendered', !!(await p.$('#panel-activity-body #av-list')));
  // D17 / task #47: screenCardFor falls back to the viewer's active screen
  // (viewerFor's `active`) when inspectorScreenId is unset, so a fresh
  // session shows the screen card the moment the pane opens — nothing has
  // been hovered or locked yet. Was previously dead code (mode was always
  // 'empty' here); this proves the fallback wiring actually renders.
  const screenId = await p.$eval('#av-list .msg-text code', (e) => e.textContent.trim()).catch(() => null);
  check('screen card renders on open (mode: screen, no hover yet)', !!screenId, screenId ?? '(none found)');
  check('not shown as locked/element chrome', !(await p.$('#av-list button[hx-post*="/design/inspector/unlock"]')));

  console.log('\n=== 2. arm inspect on portalo.home ===');
  // The tile toolbar is opacity/pointer-events gated behind :hover|:focus-within
  // (viewer.css) — a real cursor triggers that naturally, but Playwright's
  // actionability pre-check hit-tests the target before performing the
  // hover-triggering move, so it never observes pointer-events:auto. An
  // explicit hover first (which also scrolls the tile into view) sidesteps it.
  await p.hover('.dv-tile[data-id="portalo.home"]'); await s(p);
  await p.click('.dv-tile[data-id="portalo.home"] a[hx-get*="inspect="]'); await s(p);
  const fr = await p.$('.dv-tile[data-id="portalo.home"] iframe');
  const doc = await fr.contentFrame();
  check('iframe armed (data-inspect-armed)', await doc.evaluate(() => document.body.dataset.inspectArmed === 'true'));
  check('inspect.js loaded', await doc.evaluate(() => !!document._inspect));

  console.log('\n=== 3. hover [data-el="card:Ceramics"] -> pane shows it, unlocked ===');
  await doc.hover('[data-el="card:Ceramics"]'); await s(p);
  check('POST /design/inspector/select fired', reqs.some((r) => r.includes('inspector/select')));
  check('pane shows card:Ceramics', await p.$eval('#av-list .msg-text code', (e) => e.textContent.trim()) === 'card:Ceramics');
  check('not shown as locked', !(await p.$('#av-list .msg.is-active')));

  console.log('\n=== 4. click it -> locks the pane ===');
  await doc.click('[data-el="card:Ceramics"]'); await s(p);
  check('pane shows card:Ceramics, locked', await p.$eval('#av-list .msg-text code', (e) => e.textContent.trim()) === 'card:Ceramics'
    && !!(await p.$('#av-list .msg.is-active')));
  check('unlock button present', !!(await p.$('#av-list button[hx-post*="/design/inspector/unlock"]')));

  console.log('\n=== 5. hover a different element while locked -> "locked wins", pane unchanged ===');
  // tab:Home is a `position: fixed` bottom-tab-bar element; inside the scaled
  // still-preview iframe its fixed containing block is the transformed stub
  // wrapper, which places it below the visible crop — an in-flow card is a
  // reliable second target instead.
  const reqsBefore5 = reqs.length;
  await doc.hover('[data-el="card:Furniture"]'); await s(p);
  check('hover while locked still POSTed (proves the pane is unchanged despite a real request, not a dead hover)', reqs.length > reqsBefore5, `${reqsBefore5} -> ${reqs.length}`);
  check('pane still shows card:Ceramics, still locked', await p.$eval('#av-list .msg-text code', (e) => e.textContent.trim()) === 'card:Ceramics'
    && !!(await p.$('#av-list .msg.is-active')));

  console.log('\n=== 6. lock survives a full panel morph (session state, not DOM state — D16) ===');
  await p.click('a.panel-views-icon[href="/design/panel/screens"]'); await s(p);
  await p.click('a.panel-views-icon[href="/design/inspector"]'); await s(p);
  check('still locked to card:Ceramics after the round trip', await p.$eval('#av-list .msg-text code', (e) => e.textContent.trim()) === 'card:Ceramics'
    && !!(await p.$('#av-list .msg.is-active')));

  console.log('\n=== 7. pin from the pane -> chat context gains the chip, iframe is NOT reloaded ===');
  const chipsBefore = await p.evaluate(() => document.querySelectorAll('.cs-el-chip').length);
  let navs = 0;
  const onNav = (f) => { if (f !== p.mainFrame()) navs++; };
  p.on('framenavigated', onNav);
  const pinBtn = await p.$('#av-list form[hx-post="/design/chat/context/element"] button[type="submit"]');
  check('pin button present', !!pinBtn);
  if (pinBtn) { await pinBtn.click(); await waitQuiet(p); }
  p.off('framenavigated', onNav);
  const chipsAfter = await p.evaluate(() => document.querySelectorAll('.cs-el-chip').length);
  check('element chip added', chipsAfter > chipsBefore, `${chipsBefore} -> ${chipsAfter}`);
  check('inspected iframe did not navigate', navs === 0, `${navs} nav(s)`);

  console.log('\n=== 8. unlock -> drops the lock, falls back to the last hover ===');
  await p.click('#av-list button[hx-post*="/design/inspector/unlock"]'); await s(p);
  check('POST /design/inspector/unlock fired', reqs.some((r) => r.includes('inspector/unlock')));
  check('pane still shows card:Ceramics, no longer locked', await p.$eval('#av-list .msg-text code', (e) => e.textContent.trim()) === 'card:Ceramics'
    && !(await p.$('#av-list .msg.is-active')));

  console.log('\n=== 9. hover while the inspector is NOT the active view -> 204, no-op ===');
  await p.click('a.panel-views-icon[href="/design/panel/screens"]'); await s(p);
  const before = await p.$eval('#panel-activity-body', (e) => e.innerHTML);
  const reqsBefore9 = reqs.length;
  await doc.hover('[data-el="card:Lighting"]'); await s(p);
  const after = await p.$eval('#panel-activity-body', (e) => e.innerHTML);
  // The island posts on every hover regardless of which pane is open — the
  // 204 guard is server-side (prototype_viewmodel.js: inspectorSelect). If the
  // request never fired, "untouched" would be vacuously true with nothing
  // exercised, so assert the POST happened too.
  check('POST /design/inspector/select still fired (proves the guard, not a dead hover)', reqs.length > reqsBefore9, `${reqsBefore9} -> ${reqs.length}`);
  check('screens list untouched by the hover (204 no-op)', before === after);

  console.log('\n=== requests seen ===');
  console.log(reqs.length ? reqs.join('\n  ') : '  (none)');
  console.log('\n=== errors ===');
  console.log(errs.length ? errs.map((e) => '  ! ' + e).join('\n') : '  none');
  console.log(`\n${fails === 0 ? 'ALL PASS' : fails + ' FAILURE(S)'}`);
  if (fails) process.exitCode = 1;
} catch (e) { console.log('PROBE ERROR:', e.message); process.exitCode = 1; } finally { if (b) await b.close(); }
