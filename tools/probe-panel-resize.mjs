// probe-panel-resize.mjs — panels resize from their inner EDGE, and
// releasing the drag must not disturb anything else on the page.
//
// WHY THIS EXISTS: two bugs, both invisible to a server-render probe.
//
// 1. DIRECTION. drag.js computed `startW + (clientX - sx)`, which silently
//    assumes you grabbed an END edge. The composer's rail sits on its end
//    edge, the activity panel's on its start edge — a single fixed sign is
//    wrong for whichever panel doesn't match it, and the panel fought the
//    pointer: drag right, panel grows, edge runs away from the cursor. The
//    sign has to come from which edge you grabbed (`data-edge`, start|end),
//    never from `data-persist`, which is an opaque server key, not a
//    position.
//
// 2. THE FLASH. On release drag.js POSTed the new width and swapped the whole
//    panel back in. htmx runs with globalViewTransitions:true, and
//    `.panel-activity` has no `view-transition-name` of its own — so it was
//    captured in the ROOT snapshot and the browser cross-faded the ENTIRE
//    page. Letting go of the drag looked like the app reloading itself. The
//    client already holds the final width; the server only needs to record
//    it, so the request must not swap.
//
// Needs a browser: both bugs live in pointer handling and the swap's
// animation, neither of which exists in the HTML.
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { chromium } = await import(
  path.join(REPO, 'skills/appbox-designer/runtime/node_modules/playwright-core/index.mjs'));
const CHROME = process.env.APPBOX_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
import { resolveBase } from './_probe_base.mjs';
const BASE = resolveBase();

let b, fails = 0;
const check = (n, ok, x = '') => { if (!ok) fails++; console.log(`  [${ok ? 'PASS' : 'FAIL'}] ${n}${x ? ' — ' + x : ''}`); };

// Count view transitions and htmx swaps, and watch every request, so "did the
// release disturb the page?" is measured rather than eyeballed.
const instrument = (p) => p.evaluate(() => {
  window.__vt = 0;
  const orig = document.startViewTransition?.bind(document);
  if (orig) document.startViewTransition = (cb) => { window.__vt++; return orig(cb); };
  // Tag the live nodes. htmx still EMITS beforeSwap for a swap:'none' request,
  // so counting that event proves nothing — what matters is whether any node
  // was actually replaced. Morph keeps nodes; a re-render does not.
  document.querySelectorAll('.panel-activity *, .panel-composer *').forEach((n) => { n.__orig = 1; });
});
const nodesKept = (p) => p.evaluate(() => {
  const live = [...document.querySelectorAll('.panel-activity *, .panel-composer *')];
  return { kept: live.filter((n) => n.__orig).length, total: live.length };
});

const rail = (p, panel) => p.evaluate((s) => {
  const e = document.querySelector(s + ' .panel-resize');
  if (!e) return null;
  const r = e.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
}, panel);

const widthOf = (p, s) => p.evaluate((x) => Math.round(document.querySelector(x).getBoundingClientRect().width), s);

async function dragRail(p, panel, dx, from = 450) {
  await p.goto(BASE + '/design', { waitUntil: 'networkidle' });
  // Start mid-range so neither min-width nor the 600px cap masks the result.
  await p.evaluate(({ s, w }) => { document.querySelector(s).style.width = w + 'px'; }, { s: panel, w: from });
  await p.waitForTimeout(250);
  await instrument(p);
  const before = await widthOf(p, panel);
  const r = await rail(p, panel);
  const reqs = [];
  const onReq = (q) => reqs.push(q.method() + ' ' + q.url().replace(BASE, ''));
  await p.mouse.move(r.x, r.y);
  await p.mouse.down();
  await p.mouse.move(r.x + dx, r.y, { steps: 14 });
  p.on('request', onReq);              // only count what the RELEASE causes
  await p.mouse.up();
  await p.waitForTimeout(1100);
  p.off('request', onReq);
  return { before, after: await widthOf(p, panel), reqs,
           vt: await p.evaluate(() => window.__vt), nodes: await nodesKept(p) };
}

try {
  b = await chromium.launch({ executablePath: CHROME, headless: true });
  const p = await b.newPage({ viewport: { width: 1900, height: 1000 } });

  console.log('\n=== A. the rail is the edge, not an icon ===');
  await p.goto(BASE + '/design', { waitUntil: 'networkidle' });
  const rails = await p.evaluate(() => [...document.querySelectorAll('.panel-resize')].map((e) => ({
    host: e.closest('.panel-composer') ? 'composer' : 'activity',
    cursor: getComputedStyle(e).cursor,
    edge: e.dataset.edge,
    kids: e.children.length,
    aria: !!e.getAttribute('aria-label'),
    atInnerEdge: e.closest('.panel-composer')
      ? Math.abs(e.getBoundingClientRect().right - e.closest('.panel-composer').getBoundingClientRect().right) < 2
      : Math.abs(e.getBoundingClientRect().left - e.closest('.panel-activity').getBoundingClientRect().left) < 2,
  })));
  check('both panels expose a rail', rails.length === 2, JSON.stringify(rails.map((r) => r.host)));
  check('rails carry no icon', rails.every((r) => r.kids === 0), JSON.stringify(rails.map((r) => r.kids)));
  check('rails keep an aria-label', rails.every((r) => r.aria), '');
  check('rails show a col-resize cursor', rails.every((r) => r.cursor === 'col-resize'), '');
  check('each rail sits on its panel INNER edge', rails.every((r) => r.atInnerEdge),
    JSON.stringify(rails.map((r) => `${r.host}:${r.edge}=${r.atInnerEdge}`)));
  check('composer rail is its end edge, activity rail its start',
    rails.find((r) => r.host === 'composer')?.edge === 'end' && rails.find((r) => r.host === 'activity')?.edge === 'start',
    JSON.stringify(rails.map((r) => `${r.host}=${r.edge}`)));

  console.log('\n=== B. the edge follows the pointer (sign per edge) ===');
  // This section measures the SIGN and the distance, so every drag must stay
  // strictly inside both panels' limits — a clamp here would look identical to
  // an inverted or ignored drag. The tightest range is the composer's
  // [390, 500]; 445 ± 45 sits 10px clear of both ends of it. Section E is where
  // the limits themselves get tested, by overshooting them on purpose.
  for (const [label, panel, dx, want] of [
    ['composer end-edge', '.panel-composer', +45, 'wider'],
    ['composer end-edge', '.panel-composer', -45, 'narrower'],
    ['activity start-edge', '.panel-activity', +45, 'narrower'],
    ['activity start-edge', '.panel-activity', -45, 'wider'],
  ]) {
    const r = await dragRail(p, panel, dx, 445);
    const got = r.after > r.before + 5 ? 'wider' : r.after < r.before - 5 ? 'narrower' : 'unchanged';
    check(`${label}: drag ${dx > 0 ? '+' : ''}${dx} makes it ${want}`, got === want, `${r.before} -> ${r.after}`);
    check(`${label}: honours the dragged distance`,
      Math.abs(Math.abs(r.after - r.before) - Math.abs(dx)) < 18, `moved ${Math.abs(r.after - r.before)}px`);
  }

  console.log('\n=== C. releasing must not refresh the page ===');
  {
    const r = await dragRail(p, '.panel-activity', -40);
    // THE REGRESSION: a swap here cross-fades the whole document, because
    // .panel-activity has no view-transition-name and lands in the root snapshot.
    check('release starts NO view transition', r.vt === 0, `${r.vt} started`);
    check('release replaces no panel node', r.nodes.kept === r.nodes.total,
      `${r.nodes.kept}/${r.nodes.total} original nodes still live`);
    check('release still records the width server-side',
      r.reqs.some((q) => q.startsWith('POST /design/panel/size/')), JSON.stringify(r.reqs));
  }
  {
    const r = await dragRail(p, '.panel-composer', +70);
    check('composer release makes no request at all (no server width)',
      r.reqs.length === 0, JSON.stringify(r.reqs));
    check('composer release starts no view transition', r.vt === 0, `${r.vt} started`);
  }

  console.log('\n=== D. the width survives a reload ===');
  {
    // -40 from 450 lands on 490, clear of the 500 cap: a drag that clamped
    // would still "persist across a reload" while proving nothing about the
    // drag, since both sides of the comparison would be the ceiling.
    await dragRail(p, '.panel-activity', -40);
    const dragged = await widthOf(p, '.panel-activity');
    await p.goto(BASE + '/design', { waitUntil: 'networkidle' });
    const reloaded = await widthOf(p, '.panel-activity');
    check('activity width persists across a reload', Math.abs(reloaded - dragged) < 3, `${dragged} -> ${reloaded}`);
  }

  // LAST, deliberately: every drag below overshoots a limit, so it leaves the
  // activity panel pinned at 340 or 600. A section that ran after this one
  // would start from an extreme and its own drag would clamp to a no-op —
  // passing while testing nothing.
  console.log('\n=== E. the readout equals the panel (badge maths) ===');
  // THE BUG THIS CATCHES: drag.js clamped to a hardcoded [200, 600] — a pair of
  // numbers that matched NO panel. The composer floors at 360px and ceilings at
  // 576px; the activity panel floors at 340px. Past a limit, min/max-width held
  // the element still while the badge kept counting, so the readout reported
  // 160px of travel that never happened. The limits live in CSS now and drag.js
  // reads them, so the invariant is simply: the number equals the box.
  //
  // Every drag below OVERSHOOTS its limit deliberately — a drag that stays in
  // range agrees with a hardcoded clamp too, and would have passed all along.
  const badgeVsBox = async (panel, dx, from = 450) => {
    await p.goto(BASE + '/design', { waitUntil: 'networkidle' });
    await p.evaluate(({ s, w }) => { document.querySelector(s).style.width = w + 'px'; }, { s: panel, w: from });
    await p.waitForTimeout(250);
    const r = await rail(p, panel);
    await p.mouse.move(r.x, r.y);
    await p.mouse.down();
    await p.mouse.move(r.x + dx, r.y, { steps: 14 });
    // READ WHILE THE BUTTON IS STILL DOWN. pointerup removes the badge, so a
    // post-release read finds null and every assertion below passes vacuously.
    const seen = await p.evaluate((s) => {
      const el = document.querySelector(s);
      const b = el.querySelector('.panel-resize-width');
      const cs = getComputedStyle(el);
      return { badge: b ? parseFloat(b.textContent) : null,
               box: Math.round(el.getBoundingClientRect().width),
               min: parseFloat(cs.minWidth), max: parseFloat(cs.maxWidth) };
    }, panel);
    await p.mouse.up();
    await p.waitForTimeout(800);
    return seen;
  };
  for (const [label, panel, dx, end] of [
    ['composer past its floor',   '.panel-composer', -260, 'min'],
    ['composer past its ceiling', '.panel-composer', +300, 'max'],
    ['activity past its floor',   '.panel-activity', +260, 'min'],
    ['activity past its ceiling', '.panel-activity', -300, 'max'],
  ]) {
    const r = await badgeVsBox(panel, dx);
    check(`${label}: badge exists mid-drag`, r.badge !== null,
      'null badge would make the checks below vacuous');
    check(`${label}: badge equals the rendered width`,
      r.badge !== null && Math.abs(r.badge - r.box) <= 1, `badge=${r.badge} box=${r.box}`);
    check(`${label}: stops AT the CSS ${end}-width`,
      r.badge !== null && Math.abs(r.badge - r[end]) <= 1,
      `badge=${r.badge} css ${end}-width=${r[end]}`);
  }

} catch (e) {
  fails++; console.log('  [FAIL] probe threw — ' + e.message);
} finally { if (b) await b.close(); }

console.log(fails ? `\n==== ${fails} CHECK(S) FAILED ====` : '\n==== ALL CHECKS PASSED ====');
process.exit(fails ? 1 : 0);
