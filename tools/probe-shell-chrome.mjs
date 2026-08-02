// probe-shell-chrome.mjs — the viewer's two shell panels SURVIVE every swap.
//
// The regression this locks down: #viewerSwap rendered `dv.designViewer(c.viewer)`
// with no second arg while the full page rendered it WITH a chrome object, and
// design_viewer.html guards the whole <header class="dv-topbar"> behind
// `{% if chrome %}`. Every control that swaps #design-viewer — the lens chips
// (.dv-chip), the device rungs (.mini-panel-tab) and the bg swatches
// (.mini-swatch) — therefore went through the ONE render path with no chrome
// and deleted the top panel, permanently, until a full page reload. .dv-botbar
// is unguarded so the bar itself stayed, but its foot line (.dv-botbar-foot)
// is chrome and went with the header.
//
// Why probe-explode.mjs section D never saw it: section D opens with
// `await p.goto(BASE + '/design')` — a FRESH full-page navigation — and only
// then reads .dv-topbar. A full page render is the one state where chrome is
// guaranteed present, so section D samples the only passing case and never
// exercises a fragment swap at all. This probe asserts the panels AFTER each
// swap, which is the state the user is actually in.
//
// Run against a live studio:
//   dart run appboxd/bin/appbox.dart design serve designs/appbox-studio --port 4319 --json --project portalo
//   node tools/probe-shell-chrome.mjs
// Override with APPBOX_BASE / APPBOX_CHROME.
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { chromium } = await import(
  path.join(REPO, 'skills/appbox-designer/runtime/node_modules/playwright-core/index.mjs'));
const CHROME = process.env.APPBOX_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
import { resolveBase, requireDisposableProject, waitFor, trackTransitions } from './_probe_base.mjs';
const BASE = resolveBase();
// Section F below clicks a live flow-move control — mutates whatever
// project BASE is serving. See _probe_base.mjs for why this can't just
// trust --project and what "disposable" means here.
await requireDisposableProject(BASE);
let b, fails = 0;
const check = (n, ok, x = '') => { if (!ok) fails++; console.log(`  [${ok ? 'PASS' : 'FAIL'}] ${n}${x ? ' — ' + x : ''}`); };

// The panel census, read from inside .design-viewer (the fullscreen target).
const census = (p) => p.evaluate(() => {
  const v = document.querySelector('.design-viewer');
  if (!v) return null;
  const inside = (s) => !!v.querySelector(s);
  return {
    topbar: inside('.dv-topbar'),
    title: inside('.dv-topbar-title'),
    botbar: inside('.dv-botbar'),
    foot: inside('.dv-botbar-foot'),
    miniDocked: inside('.dv-botbar .mini-panel'),
    acts: [...v.querySelectorAll('.dv-shell-act')].map((a) => ({
      tag: a.tagName, disabled: a.disabled === true, label: a.getAttribute('aria-label'),
      post: a.getAttribute('hx-post'),
    })),
    danger: v.querySelectorAll('.is-danger').length,
  };
});

// Every control that swaps #design-viewer went through the chromeless path.
// Selected by INDEX, never by href: withParams elides defaults (mobile drops
// vp=, views drops mode=) and echoes whatever else is live, so an href matcher
// would miss and p.click() would throw the whole run into the catch. DEVICES
// order is mobile/tablet/desktop, lens order views/flows/proto.
// A swap re-renders #panelsSwap, and every caller below reads the panels right
// afterwards. The old fixed 1200ms guessed how long that takes; the DOM offers
// no honest post-condition (the stage and .design-viewer are present both
// before and after, so any check on them is satisfied instantly and waits for
// nothing). htmx's own afterSettle counter is the unambiguous signal, and
// waitFor then drains the view transition the swap runs inside.
const settleCount = (p) => p.evaluate(() => window.__hxSettled || 0);
const awaitSwap = async (p, before) =>
  waitFor(p, (n) => (window.__hxSettled || 0) > n,
    { arg: before, label: 'htmx to settle the panel swap', timeout: 8000 });

const swapNth = async (p, sel, i) => {
  const els = await p.$$(sel);
  if (!els[i]) throw new Error(`no ${sel}[${i}] (found ${els.length})`);
  const before = await settleCount(p);
  await els[i].click();
  await awaitSwap(p, before);
};
const swap = async (p, sel) => {
  const before = await settleCount(p);
  await p.click(sel);
  await awaitSwap(p, before);
};

try {
  b = await chromium.launch({ executablePath: CHROME, headless: true });
  const p = await b.newPage({ viewport: { width: 1800, height: 1100 } });
  await trackTransitions(p);
  const pageErrors = [];
  p.on('pageerror', (e) => pageErrors.push(e.message));
  await p.goto(BASE + '/design', { waitUntil: 'networkidle' });
  await waitFor(p, () => {
    const v = document.querySelector('.design-viewer');
    return !!v && !!v.querySelector('.dv-shell-act');
  }, { label: 'the viewer shell + its chrome actions', timeout: 15000 });

  // Asserted in every state below, so the shape lives here once.
  const panelsOk = (label, s) => {
    check(`${label}: top panel present`, !!s && s.topbar);
    check(`${label}: title present`, !!s && s.title);
    check(`${label}: bottom panel present`, !!s && s.botbar);
    check(`${label}: foot line present`, !!s && s.foot);
    check(`${label}: mini panel docked in the bottom panel`, !!s && s.miniDocked);
    check(`${label}: zero is-danger nodes`, !!s && s.danger === 0, s ? String(s.danger) : 'no viewer');
  };

  console.log('=== A. first load ===');
  const first = await census(p);
  panelsOk('first load', first);

  console.log('\n=== B. viewport rungs (.mini-panel-tab) — each one used to delete the top panel ===');
  for (const [i, vp] of [[1, 'tablet'], [2, 'desktop'], [0, 'mobile']]) {
    await swapNth(p, '.mini-panel-tab', i);
    panelsOk(`rung ${vp}`, await census(p));
  }

  console.log('\n=== C. bg swatches (.mini-swatch) — same swap target, same defect ===');
  for (const bg of ['warm', 'slate', 'canvas']) {
    await swap(p, `.mini-swatch-${bg}`);
    panelsOk(`bg ${bg}`, await census(p));
  }

  console.log('\n=== D. lens switches (.dv-chip) — views / flows / proto ===');
  for (const [i, mode] of [[1, 'flows'], [2, 'proto'], [0, 'views']]) {
    await swapNth(p, '.dv-chip', i);
    panelsOk(`lens ${mode}`, await census(p));
  }

  console.log('\n=== E. chrome.actions is exactly canvas undo + redo ===');
  const acts = (await census(p)).acts;
  check('exactly two shell actions', acts.length === 2, String(acts.length));
  check('both are buttons (mutations, not links)', acts.every((a) => a.tag === 'BUTTON'), acts.map((a) => a.tag).join(','));
  check('action 1 POSTs canvas undo', acts[0]?.post === '/design/undo/canvas', acts[0]?.post);
  check('action 2 POSTs canvas redo', acts[1]?.post === '/design/redo/canvas', acts[1]?.post);
  // A fresh session has stepped nothing, so BOTH ends of the stack are empty.
  check('undo disabled at the bottom of the stack', acts[0]?.disabled === true);
  check('redo disabled at the top of the stack', acts[1]?.disabled === true);

  console.log('\n=== F. a canvas mutation arms undo, and undoing re-arms redo ===');
  // A flow nudge is the cheapest canvas entry: it pushes onto undoStacks.canvas.
  // :not([disabled]) matters — tile 1's move-earlier renders disabled, and
  // clicking it would push nothing and fail the undo-enabled check spuriously.
  await swapNth(p, '.dv-chip', 1);
  const nudge = await p.$('.dv-tool[hx-post*="/move/"]:not([disabled])');
  if (!nudge) { check('found a flow move button to arm the stack', false); }
  else {
    // The tool is CSS hover-revealed (dv-tile-chrome sits above it until
    // :hover/:focus-within). A real hover on the always-visible tile first
    // opens the gate, then a plain click exercises the real reveal — force:
    // true would bypass the actionability check entirely and keep passing
    // even if the hover-reveal itself broke (task #49).
    const tileId = await nudge.evaluate((el) => el.closest('.dv-tile')?.dataset.id);
    await p.hover(`.dv-tile[data-id="${tileId}"]`);
    // flowMove and undo/redo are async (facade.undo awaits a file write), and
    // #panelsSwap re-renders the whole stage — a fixed wait-then-read races
    // that write under load (task #48/#50 root cause: a flake, not session
    // contamination). Poll the actual condition each check exists to prove,
    // not a fixed delay or a proxy like "a request finished".
    await nudge.click();
    // A BARE p.waitForFunction here used to THROW on timeout, and the throw
    // aborted the whole run from inside the try — so a slow undo/redo silently
    // deleted the eight checks below (the post-undo panel census, the redo
    // assertion, and the page-error check) and the run still reported "1
    // FAILED" with no indication that eight assertions never executed.
    //
    // That is how a real defect hid: a summary counting [FAIL] lines saw none,
    // because the failure arrived as PROBE ERROR instead. waitFor warns and
    // returns false, so the checks below run and report the ACTUAL state.
    // A probe must report what it found, not stop at the first surprise.
    await waitFor(
      p,
      () => document.querySelector('.design-viewer .dv-shell-act[hx-post="/design/undo/canvas"]')?.disabled === false,
      { label: 'undo to become enabled after a flow move', timeout: 5000 },
    );
    const armed = await census(p);
    panelsOk('after a flow move', armed);
    check('undo enabled once the canvas stack is non-empty', armed.acts[0]?.disabled === false);
    check('redo still disabled (nothing stepped back yet)', armed.acts[1]?.disabled === true);

    await p.click('.dv-shell-act[hx-post="/design/undo/canvas"]');
    // THIS is the one that fails under concurrent load (task #55): redo stays
    // disabled well past 5s, and past 20s in an independent run. Reported as a
    // failed check, not as an aborted run — the difference decides whether the
    // next reader sees a product defect or a broken probe.
    await waitFor(
      p,
      () => document.querySelector('.design-viewer .dv-shell-act[hx-post="/design/redo/canvas"]')?.disabled === false,
      { label: 'redo to re-enable after undo', timeout: 5000 },
    );
    const stepped = await census(p);
    panelsOk('after undo', stepped);
    check('redo enabled after stepping back', stepped.acts[1]?.disabled === false);
  }

  check('no page errors', pageErrors.length === 0, pageErrors.join(' | '));
} catch (e) { console.log('PROBE ERROR:', e.message); fails++; }
finally { if (b) await b.close(); console.log(`\n==== ${fails ? fails + ' FAILED' : 'ALL CHECKS PASSED'} ====`); }
