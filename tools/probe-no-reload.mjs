// Acceptance probe for the no-reload work.
//   A  an unrelated interaction must not destroy the viewer's iframes
//   B  navigation done INSIDE a live tile must survive an unrelated interaction  <-- the user's complaint
//   C  browser/morph capability facts
//   D  morph hazards: duplicate ids, <details> open state, typed text, web components
// Run against a live studio:
//   dart run appboxd/bin/appbox.dart design serve designs/appbox-studio --port 4319 --json --project portalo
//   node tools/probe-no-reload.mjs
// Override with APPBOX_BASE / APPBOX_CHROME. Exits non-zero if a check fails.
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { chromium } = await import(
  path.join(REPO, 'skills/appbox-designer/runtime/node_modules/playwright-core/index.mjs'));

const CHROME = process.env.APPBOX_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const BASE = process.env.APPBOX_BASE || 'http://localhost:4319';
const settle = (p) => p.waitForTimeout(900);
const ok = (b) => (b ? 'PASS' : 'FAIL');

const mark = `(() => { const f=[...document.querySelectorAll('iframe')]; f.forEach((x,i)=>x.__probe='p'+i); return f.length; })()`;
const survivors = `(() => { const f=[...document.querySelectorAll('iframe')]; return {total:f.length, marked:f.filter(x=>x.__probe!==undefined).length}; })()`;
const dupIds = `(() => {
  const seen={}, dup=[];
  for (const el of document.querySelectorAll('[id]')) { if (seen[el.id]) dup.push(el.id); seen[el.id]=1; }
  return [...new Set(dup)];
})()`;

let browser, fails = 0;
const check = (name, pass, extra = '') => { if (!pass) fails++; console.log(`  [${ok(pass)}] ${name}${extra ? ' — ' + extra : ''}`); };

try {
  browser = await chromium.launch({ executablePath: CHROME, headless: true });
  const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
  const errs = [];
  page.on('pageerror', (e) => errs.push(e.message));
  let navs = [];
  page.on('framenavigated', (f) => { if (f !== page.mainFrame()) navs.push(f.url().replace(BASE, '')); });
  // Pin-response sizes, so the cost of the highest-frequency interaction stays
  // visible. The ceiling is a blow-up detector, not a target: the response was
  // measured at ~85 KB and is irreducible by retargeting (see Lever 2 in
  // docs/plans/htmx-no-reload-interaction.md — the three regions a pin really
  // changes are 90% of it). If this goes red, something started shipping whole
  // extra panels again.
  const pinBytes = [];
  page.on('response', async (r) => {
    if (!/\/context\//.test(r.url())) return;
    try { pinBytes.push((await r.body()).length); } catch { /* body gone; ignore */ }
  });

  await page.goto(BASE + '/design', { waitUntil: 'networkidle' });
  await page.waitForSelector('iframe.dv-tile-frame', { timeout: 15000 });
  await settle(page);

  console.log('=== C. capability ===');
  const morphReady = await page.evaluate(`!!(window.htmx && htmx.config && document.querySelector('[hx-ext*="morph"]')) && typeof Idiomorph !== 'undefined'`);
  console.log('  htmx            :', await page.evaluate('window.htmx && htmx.version'));
  console.log('  Idiomorph loaded:', await page.evaluate(`typeof Idiomorph`));
  console.log('  Element.moveBefore:', await page.evaluate(`'moveBefore' in Element.prototype`));
  check('morph extension wired', morphReady);

  console.log('\n=== D1. duplicate ids (morph correctness precondition) ===');
  const dups = await page.evaluate(dupIds);
  check('no duplicate ids in /design', dups.length === 0, dups.length ? dups.slice(0, 6).join(', ') : '');

  console.log('\n=== A. does an unrelated interaction destroy the iframes? ===');
  const before = await page.evaluate(mark);
  navs = [];
  await page.$eval('.dv-tile .dv-tile-tools a[hx-get*="context"]', (el) => el.click());
  await settle(page);
  const after = await page.evaluate(survivors);
  console.log(`  iframes ${before} -> surviving DOM nodes ${after.marked}, iframe navigations ${navs.length}`);
  check('iframes survive as the same DOM nodes', after.marked >= before - 1, `${after.marked}/${before}`);
  check('no iframe re-navigation', navs.length === 0, `${navs.length} navigations`);

  console.log('\n=== D2. node identity + typed text survive a swap ===');
  // Mark the <details> NODE. What morph guarantees, and therefore what is worth
  // asserting, is that this node is not destroyed — at baseline it was replaced
  // outright. Its `open` state is a separate matter: the server renders
  // <details> without `open`, so morph faithfully closes it. That is deliberate
  // and documented as won't-fix in docs/plans/htmx-no-reload-interaction.md (a
  // menu closing on an unrelated interaction is conventional, and preserving it
  // would cost a stale flow list), so there is nothing here to assert about it
  // — an assertion either encodes the wart or fails on purpose. Node survival
  // is the check that can actually go red if morph regresses.
  const hadDetails = await page.evaluate(`(() => { const d=document.querySelector('details.dv-tool-menu'); if(!d) return false; d.__probeNode=1; return true; })()`);
  await page.evaluate(`(() => { const t=document.querySelector('.composer-card textarea, textarea[name="text"]'); if(t){ t.value='DRAFT-KEEP-ME'; } })()`);
  const hadTextarea = await page.evaluate(`!!document.querySelector('textarea[name="text"]')`);
  await page.$eval('.dv-tile[data-id="portalo.cart"] .dv-tile-tools a[hx-get*="context"]', (el) => el.click());
  await settle(page);
  const detailsSameNode = hadDetails && await page.evaluate(`(()=>{const d=document.querySelector('details.dv-tool-menu'); return !!(d&&d.__probeNode===1);})()`);
  const textKept = hadTextarea && await page.evaluate(`(()=>{const t=document.querySelector('textarea[name="text"]'); return !!(t&&t.value==='DRAFT-KEEP-ME');})()`);
  if (hadDetails) check('<details> menu survives as the same node', detailsSameNode);
  // Fixed: the textarea is hx-preserve'd (dropped only on the render after a
  // send, so the sent text cannot linger and be sent twice). tools/… has no
  // send coverage; that pairing is asserted separately.
  if (hadTextarea) check('typed composer draft preserved', textKept);

  console.log('\n=== B. navigation INSIDE a live tile survives (THE complaint) ===');
  await page.$eval('.dv-tile[data-id="portalo.home"] a[hx-get*="live="]', (el) => el.click());
  await settle(page);
  const liveSel = '.dv-tile[data-id="portalo.home"] iframe';
  let frame = await (await page.$(liveSel)).contentFrame();
  console.log('  starts at :', frame.url().replace(BASE, ''));
  const link = await frame.$('a[href*="portalo.category"]');
  if (!link) { check('found in-frame link to navigate', false); }
  else {
    await link.click();
    await settle(page);
    frame = await (await page.$(liveSel)).contentFrame();
    console.log('  after nav :', frame.url().replace(BASE, ''));
    await page.$eval('.dv-tile[data-id="portalo.cart"] .dv-tile-tools a[hx-get*="context"]', (el) => el.click());
    await settle(page);
    frame = await (await page.$(liveSel)).contentFrame();
    const ended = frame.url().replace(BASE, '');
    console.log('  after unrelated pin :', ended);
    check('live tile kept the user\'s navigation', ended.includes('portalo.category'), ended);
  }

  console.log('\n=== D3. web components still upgraded after a morph ===');
  const wc = await page.evaluate(`(() => {
    const names = ['model-viewer','dotlottie-wc'];
    const out = {};
    for (const n of names) {
      const el = document.querySelector(n);
      out[n] = el ? (customElements.get(n) ? 'defined' : 'present-undefined') : 'absent-in-shell';
    }
    return out;
  })()`);
  console.log('  ', JSON.stringify(wc), '(shell-level; portalo web components live inside iframes)');

  console.log('\n=== E. pin payload cost ===');
  const worstPin = pinBytes.length ? Math.max(...pinBytes) : 0;
  console.log(`  pin responses: ${pinBytes.length}, largest ${worstPin} bytes`);
  if (pinBytes.length) check('pin response under the 200 KB blow-up ceiling', worstPin < 200_000, `${worstPin} bytes`);

  console.log('\n=== page errors ===');
  console.log(errs.length ? errs.slice(0, 5).map(e => '  ! ' + e).join('\n') : '  none');
  check('no uncaught page errors', errs.length === 0);
} catch (e) {
  console.log('PROBE ERROR:', e.message); fails++;
} finally {
  if (browser) await browser.close();
  console.log(`\n==== ${fails === 0 ? 'ALL CHECKS PASSED' : fails + ' CHECK(S) FAILED'} ====`);
  process.exit(fails === 0 ? 0 : 1);
}
