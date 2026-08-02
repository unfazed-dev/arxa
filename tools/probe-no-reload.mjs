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

  console.log('\n=== D2. <details> open state + typed text survive a swap ===');
  await page.evaluate(`(() => { const d=document.querySelector('details.dv-tool-menu'); if(d) d.open=true; })()`);
  const hadDetails = await page.evaluate(`!!document.querySelector('details.dv-tool-menu')`);
  await page.evaluate(`(() => { const t=document.querySelector('.composer-card textarea, textarea[name="text"]'); if(t){ t.value='DRAFT-KEEP-ME'; } })()`);
  const hadTextarea = await page.evaluate(`!!document.querySelector('textarea[name="text"]')`);
  await page.$eval('.dv-tile[data-id="portalo.cart"] .dv-tile-tools a[hx-get*="context"]', (el) => el.click());
  await settle(page);
  // DEFERRED, not fixed by morph, and NOT a regression — verified by stashing
  // the templates and re-running: at baseline these nodes were DESTROYED
  // (sameNode:false) and lost the same state. Morph now keeps the node but
  // still applies the server's content, and the server echoes neither `open`
  // nor the draft text. The real fix is Lever 2 (a pin toggle should not
  // re-render the composer at all), not a bigger hammer here. Reported, and
  // deliberately excluded from this slice's pass/fail.
  const detailsOpen = hadDetails && await page.evaluate(`(()=>{const d=document.querySelector('details.dv-tool-menu'); return !!(d&&d.open);})()`);
  const textKept = hadTextarea && await page.evaluate(`(()=>{const t=document.querySelector('textarea[name="text"]'); return !!(t&&t.value==='DRAFT-KEEP-ME');})()`);
  // Fixed: the textarea is hx-preserve'd (dropped only on the render after a
  // send, so the sent text cannot linger and be sent twice). tools/… has no
  // send coverage; that pairing is asserted separately.
  if (hadTextarea) check('typed composer draft preserved', textKept);
  // Still open: the server echoes <details> without `open`, so morph closes it.
  // Not a regression — at baseline the node was destroyed outright.
  console.log(`  [KNOWN-OPEN] <details> stayed open      : ${detailsOpen} (baseline: false — node destroyed)`);
  console.log('               server does not echo `open`; morph applies server state faithfully.');

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
