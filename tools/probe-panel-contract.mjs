// probe-panel-contract.mjs — the shell's panel/section contract holds.
//
// WHY THIS EXISTS: the vocabulary in
// designs/appbox-studio/ui/common/_integration_panels.md is a CONTRACT, and
// every way it breaks is invisible in the HTML.
//
//  - A panel that loses its card chrome still renders; it just stops matching
//    its neighbours, and nobody notices until the three are seen together.
//  - A section that lands in the wrong grid area still renders — the filmstrip
//    simply stops being full-height-of-the-rows, or the canvas quietly loses
//    width to a stray child auto-placed into the side-start track. That last
//    one really happened: the fullscreen-close button had no grid area and
//    took 33px off the canvas.
//  - A duplicated view-transition-name makes Chrome abort the WHOLE
//    transition, disabling view transitions app-wide with no error (ADR-0003).
//  - A section rendered empty is a bordered strip with nothing in it — the
//    exact thing "sections turn on by having content" exists to prevent.
//
// Needs a browser: all of it is computed style and grid geometry.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { chromium } = await import(path.join(REPO, 'skills/appbox-designer/runtime/node_modules/playwright-core/index.mjs'));
const CHROME = process.env.APPBOX_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
import { resolveBase } from './_probe_base.mjs';
const BASE = resolveBase();
let fails = 0;
const check = (n, ok, x = '') => { if (!ok) fails++; console.log(`  [${ok ? 'PASS' : 'FAIL'}] ${n}${x ? ' — ' + x : ''}`); };

const b = await chromium.launch({ executablePath: CHROME, headless: true });
const p = await b.newPage({ viewport: { width: 1900, height: 1000 } });
await p.goto(BASE + '/design', { waitUntil: 'networkidle' });

console.log('\n=== A. every panel is a card with the SAME shadow ===');
const shadows = await p.evaluate(() => ['.panel-composer', '.panel-viewer', '.panel-activity']
  .map((s) => { const e = document.querySelector(s); return { s, shadow: e && getComputedStyle(e).boxShadow }; }));
check('all three content panels carry a shadow', shadows.every((r) => r.shadow && r.shadow !== 'none'),
  JSON.stringify(shadows.map((r) => `${r.s}=${r.shadow ? 'set' : 'MISSING'}`)));
check('the three shadows are IDENTICAL', new Set(shadows.map((r) => r.shadow)).size === 1,
  shadows.map((r) => r.shadow).join(' || '));

console.log('\n=== B. sections place by grid area ===');
const geo = await p.evaluate(() => {
  const v = document.querySelector('.panel-viewer');
  const box = (s) => { const e = v.querySelector(s); if (!e) return null; const r = e.getBoundingClientRect(); return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height), r: Math.round(r.right), b: Math.round(r.bottom) }; };
  const vr = v.getBoundingClientRect();
  return { panel: { x: Math.round(vr.x), y: Math.round(vr.y), w: Math.round(vr.width), r: Math.round(vr.right), b: Math.round(vr.bottom) },
    top: box('.panel-top'), body: box('.panel-body'), bottom: box('.panel-bottom'), side: box('.panel-side-end') };
});
check('top spans the full panel width', geo.top && Math.abs(geo.top.w - geo.panel.w) <= 2, `top=${geo.top?.w} panel=${geo.panel.w}`);
check('bottom spans the full panel width', geo.bottom && Math.abs(geo.bottom.w - geo.panel.w) <= 2, `bottom=${geo.bottom?.w} panel=${geo.panel.w}`);
check('side-end sits to the RIGHT of the body', geo.side && geo.body && geo.side.x >= geo.body.r - 2, `body.right=${geo.body?.r} side.x=${geo.side?.x}`);
check('side-end starts BELOW the top section', geo.side && geo.top && geo.side.y >= geo.top.b - 2, `top.bottom=${geo.top?.b} side.y=${geo.side?.y}`);
check('side-end ends ABOVE the bottom section', geo.side && geo.bottom && geo.side.b <= geo.bottom.y + 2, `side.bottom=${geo.side?.b} bottom.y=${geo.bottom?.y}`);
// The filmstrip is a nested card inside the side-end slot: it keeps a .6rem
// margin so its rounded corners have room to round against. So it is NOT
// flush — what must hold is that its inset is SYMMETRIC and that the body
// plus the whole side column account for the panel width with nothing lost.
const inset = await p.evaluate(() => {
  const e = document.querySelector('.panel-side-end'); const cs = getComputedStyle(e);
  return { l: cs.marginLeft, r: cs.marginRight };
});
check('side-end inset is symmetric', inset.l === inset.r, JSON.stringify(inset));
const m = parseFloat(inset.l) || 0;
check('body + side + its margins fill the panel width',
  geo.body && geo.side && Math.abs((geo.body.w + geo.side.w + 2 * m) - geo.panel.w) <= 4,
  `${geo.body?.w} + ${geo.side?.w} + 2*${m} vs ${geo.panel.w}`);
check('NO stray grid item stole the side-start column', geo.body && Math.abs(geo.body.x - geo.panel.x) <= 2,
  `body.x=${geo.body?.x} panel.x=${geo.panel.x} — a gap here means an unplaced child auto-placed into side-start`);

console.log('\n=== C. section on/off is real (no empty strips) ===');
const empties = await p.evaluate(() => [...document.querySelectorAll('.panel-top, .panel-bottom, .panel-side-start, .panel-side-end')]
  .filter((e) => !e.textContent.trim() && !e.children.length)
  .map((e) => e.className));
check('no section rendered empty', empties.length === 0, JSON.stringify(empties));
const composer = await p.evaluate(() => {
  const c = document.querySelector('.panel-composer');
  return { top: !!c.querySelector('.panel-top'), body: !!c.querySelector('.panel-body'), bottom: !!c.querySelector('.panel-bottom') };
});
check('composer: top ON', composer.top === true);
check('composer: body ON', composer.body === true);
check('composer: bottom OFF', composer.bottom === false, JSON.stringify(composer));
const hf = await p.evaluate(() => ['.panel-header', '.panel-footer'].map((s) => {
  const e = document.querySelector(s); if (!e) return { s, missing: true };
  return { s, top: !!e.querySelector('.panel-top'), body: !!e.querySelector('.panel-body'), bottom: !!e.querySelector('.panel-bottom') };
}));
check('header and footer are BODY-ONLY', hf.every((r) => !r.missing && r.body && !r.top && !r.bottom), JSON.stringify(hf));

console.log('\n=== D. view-transition names stay unique (ADR-0003) ===');
const vt = await p.evaluate(() => [...document.querySelectorAll('.panel')]
  .map((e) => getComputedStyle(e).viewTransitionName).filter((n) => n && n !== 'none'));
check('no duplicate view-transition-name among panels', new Set(vt).size === vt.length, JSON.stringify(vt));

console.log('\n=== E. header chrome survived the body wrapper ===');
const head = await p.evaluate(() => {
  const b = document.querySelector('.panel-header > .panel-body');
  if (!b) return { missing: true };
  const cs = getComputedStyle(b);
  const brand = document.querySelector('.shell-brand')?.getBoundingClientRect();
  return { dir: cs.flexDirection, items: b.children.length, brandVisible: !!brand && brand.width > 0,
           bg: getComputedStyle(document.querySelector('.panel-header')).backgroundColor };
});
check('header body is a horizontal row', head.dir === 'row', JSON.stringify(head));
check('header still has its chrome children', head.items > 3, `children=${head.items}`);
check('brand is visible', head.brandVisible === true);
check('header keeps its translucent fill', head.bg && !/^rgb\(\d+, \d+, \d+\)$/.test(head.bg), head.bg);

console.log('\n=== F. scrollbar thumb floor ===');
const thumb = await p.evaluate(() => {
  const s = [...document.styleSheets].flatMap((sh) => { try { return [...sh.cssRules]; } catch { return []; } })
    .find((r) => r.selectorText === '::-webkit-scrollbar-thumb');
  return s?.style.minHeight || null;
});
check('thumb has an explicit min-height floor', !!thumb, String(thumb));

console.log('\n=== G. the main panel matches its neighbours on a FILE READ too ===');
// Not just on the design canvas. main's card is .panel-viewer there and
// .mp-content here; if only one carries the chrome, main matches its
// neighbours on one surface and visibly does not on the other.
{
  // File links live behind the activity panel's FILES view, not on the canvas.
  await p.goto(BASE + '/design', { waitUntil: 'networkidle' });
  await p.click('a.panel-views-icon[href="/design/panel/files"]').catch(() => {});
  await p.waitForTimeout(700);
  const file = await p.evaluate(() => {
    const a = document.querySelector('#panel-activity-body a[hx-get*="/design/file"], a[href*="/design/file"]');
    return a ? (a.getAttribute('href') || a.getAttribute('hx-get')) : null;
  });
  if (!file) { console.log('  [SKIP] no file link on this surface'); }
  else {
    await p.goto(BASE + file, { waitUntil: 'networkidle' });
    const r = await p.evaluate(() => {
      const mc = document.querySelector('.mp-content');
      const cp = document.querySelector('.panel-composer');
      if (!mc || !cp) return { missing: true };
      return { mc: getComputedStyle(mc).boxShadow, cp: getComputedStyle(cp).boxShadow,
               passthrough: !!document.querySelector('.mp-content > .evidence-artifact') };
    });
    check('a file read gives main the same shadow as the composer',
      !r.missing && (r.passthrough || r.mc === r.cp), JSON.stringify(r));
  }
}

console.log('\n=== H. header menus are not clipped by the panel card ===');
// .panel sets overflow:hidden so tall panels scroll inside their rounded
// corners. The header is exactly --nav-h tall and its two <details> menus open
// DOWNWARD out of that box — and they only exist at <=839px, where they ARE
// the navigation. Inheriting the clip kills small-screen nav while every
// desktop render still looks perfect.
for (const w of [599, 800]) {
  await p.setViewportSize({ width: w, height: 900 });
  await p.goto(BASE + '/design', { waitUntil: 'networkidle' });
  const r = await p.evaluate(() => {
    const head = document.querySelector('.panel-header');
    const hb = head.getBoundingClientRect();
    const out = [];
    for (const d of head.querySelectorAll('details')) {
      d.open = true;
      const menu = d.querySelector('.drawer-panel, .overflow-menu');
      if (!menu) continue;
      const m = menu.getBoundingClientRect();
      const cs = getComputedStyle(menu);
      out.push({ cls: menu.className, h: Math.round(m.height),
                 spills: Math.round(m.bottom) > Math.round(hb.bottom),
                 visible: cs.display !== 'none' && cs.visibility !== 'hidden' && m.height > 0 });
      d.open = false;
    }
    return { headOverflow: getComputedStyle(head).overflow, menus: out };
  });
  check(`@${w}px header does not clip its own box`, r.headOverflow === 'visible', r.headOverflow);
  check(`@${w}px every header menu renders with real height`,
    r.menus.length > 0 && r.menus.every((m) => m.visible), JSON.stringify(r.menus));
}
console.log('\n=== I. the side panels shed their desktop width below 840px ===');
// The composer and the activity panel carry a fixed width, a floor and a
// shared 500px cap on desktop. Below 840px they stack one at a time and must
// release all three — and the @media rule that releases them lost on source
// order twice over: `.panel-activity` is declared later in panels.css, and
// `.panel-composer` is declared in composer.css, which loads after it. So the
// rule silently did nothing and the composer sat at its 390px desktop width
// inside a ~700px column. Desktop rendered perfectly throughout, which is why
// this is asserted rather than eyeballed.
for (const vw of [1900, 839, 800, 599]) {
  await p.setViewportSize({ width: vw, height: 900 });
  for (const role of ['composer', 'activity']) {
    await p.goto(`${BASE}/design?panel=${role}`, { waitUntil: 'networkidle' });
    const r = await p.evaluate((sel) => {
      const row = document.querySelector('.panels');
      const e = document.querySelector(sel);
      if (!e || !row) return null;
      const cs = getComputedStyle(e);
      const rs = getComputedStyle(row);
      const inner = row.getBoundingClientRect().width
        - parseFloat(rs.paddingLeft) - parseFloat(rs.paddingRight);
      return { w: e.getBoundingClientRect().width, inner,
               min: cs.minWidth, max: cs.maxWidth };
    }, '.panel-' + role);
    if (!r) { check(`@${vw}px ${role} panel present`, false, 'not found'); continue; }
    if (vw < 840) {
      // A mismatch here means a desktop width leaked past the media query.
      check(`@${vw}px ${role} fills the stacked column`, Math.abs(r.w - r.inner) <= 2,
        `panel=${Math.round(r.w)} column=${Math.round(r.inner)}`);
      check(`@${vw}px ${role} releases its floor and cap`, parseFloat(r.min) === 0 && r.max === 'none',
        `min=${r.min} max=${r.max}`);
    } else {
      check(`@${vw}px ${role} keeps the shared 500px cap`, r.max === '500px', `max=${r.max}`);
    }
  }
}
// Both side panels cap at the SAME width — the whole point of --panel-max-w.
await p.setViewportSize({ width: 1900, height: 1000 });
await p.goto(BASE + '/design', { waitUntil: 'networkidle' });
const caps = await p.evaluate(() => ['.panel-composer', '.panel-activity']
  .map((s) => getComputedStyle(document.querySelector(s)).maxWidth));
check('composer and activity share ONE ceiling', new Set(caps).size === 1, JSON.stringify(caps));

console.log('\n=== J. the main panel FILLS its slot on every shell ===');
// THE BUG THIS CATCHES: `.step-stage` is `.mp-content` — the main panel's own
// card — and it carried `max-width: 44rem; margin: 0 auto`. So on intake the
// card shrank to 44rem and floated mid-slot with ~200px of dead space either
// side, while the design shell's card filled the same slot edge to edge. Two
// shells, two visibly different main panels, from one property on the wrong
// element. The rule: the CARD fills the slot; the reading measure belongs to
// the CONTENT inside it.
//
// Asserted against the SLOT, not against a number: the slot is whatever the
// composer and the activity panel leave behind, so this keeps holding when a
// side panel is resized, and it is the same check on a shell that renders no
// side panels at all (the card then takes the whole row).
for (const route of ['/intake', '/design', '/build']) {
  await p.goto(BASE + route, { waitUntil: 'networkidle' });
  const r = await p.evaluate(() => {
    const slot = document.querySelector('.panel-main');
    // .panel-viewer when the viewer IS the card, .mp-content otherwise.
    const card = slot && slot.querySelector('.panel-viewer, .mp-content');
    if (!slot || !card) return null;
    const measured = document.querySelector('.artifact-lede');
    return { slot: slot.getBoundingClientRect().width,
             card: card.getBoundingClientRect().width,
             lede: measured ? measured.getBoundingClientRect().width : null };
  });
  if (!r) { check(`${route}: main panel has a card`, false, 'slot or card missing'); continue; }
  check(`${route}: the card fills the main slot`, Math.abs(r.card - r.slot) <= 2,
    `card=${Math.round(r.card)} slot=${Math.round(r.slot)}`);
  // The payoff for capping with a grid track instead of `> * { max-width }`:
  // a child's own, narrower measure survives. 40rem = 640px at the 16px root.
  if (r.lede !== null) {
    check(`${route}: content keeps its own narrower measure`, Math.round(r.lede) === 640,
      `.artifact-lede=${Math.round(r.lede)} (want 640)`);
  }
}
// Same slot, same card width, whatever the shell — the user-visible claim.
const cards = [];
for (const route of ['/intake', '/design']) {
  await p.goto(BASE + route, { waitUntil: 'networkidle' });
  cards.push(await p.evaluate(() => {
    const c = document.querySelector('.panel-main .panel-viewer, .panel-main .mp-content');
    return c ? Math.round(c.getBoundingClientRect().width) : null;
  }));
}
check('intake and design main panels are the SAME width', cards[0] !== null && cards[0] === cards[1],
  JSON.stringify(cards));

console.log('\n=== K. the page never scrolls; the panels do ===');
// THE BUG THIS CATCHES: the shell was `min-height: 100dvh` with the panels row
// sized `calc(100dvh - var(--nav-h) - var(--tl-h))` — a height derived from
// tokens describing two SIBLINGS the row does not own. `--tl-h` measures
// .timeline, the strip; the footer PANEL around it adds a border, so the
// column summed to 100.97dvh. One pixel: a real document scrollbar, and far
// too small to read as anything but a rendering artefact.
//
// Asserted as `scrollHeight === clientHeight`, which catches ANY overflow,
// not the specific pixel — the row is flex-sized now precisely so no future
// chrome change can re-derive itself out of sync.
await p.setViewportSize({ width: 1900, height: 1000 });
// Section D opened a FILE into the main panel, and which surface /design shows
// is server-side session state — so by now /design renders that read, not the
// canvas, and the reachability check below would measure a doc with nothing to
// scroll and blame the layout. Back out of it first: `.mp-file-back` is the
// file view's own close affordance, so this restores whatever surface the
// shell was on rather than assuming one.
await p.goto(BASE + '/design', { waitUntil: 'networkidle' });
const back = await p.evaluate(() => {
  const a = document.querySelector('.mp-file-back');
  return a ? a.getAttribute('href') : null;
});
if (back) await p.goto(BASE + back, { waitUntil: 'networkidle' });

for (const route of ['/intake', '/design', '/build']) {
  await p.goto(BASE + route, { waitUntil: 'networkidle' });
  const r = await p.evaluate(() => {
    const de = document.documentElement, f = document.querySelector('#panel-footer');
    // The scroll containers that MUST keep working — the lock is only correct
    // if the content it stops the page from scrolling is reachable elsewhere.
    const inner = [...document.querySelectorAll('.panels *')]
      .filter((e) => e.scrollHeight > e.clientHeight + 1).length;
    return { scrollH: de.scrollHeight, clientH: de.clientHeight, inner,
             tallest: Math.max(0, ...[...document.querySelectorAll('.panels *')]
               .map((e) => e.scrollHeight - e.clientHeight)),
             footerOnScreen: f ? Math.round(f.getBoundingClientRect().bottom) <= window.innerHeight : null };
  });
  check(`${route}: the page cannot scroll`, r.scrollH === r.clientH,
    `document ${r.scrollH}/${r.clientH}`);
  check(`${route}: the footer stays on screen`, r.footerOnScreen !== false,
    'a scrolling page drags the chrome out of view');
  // THE LOCK MUST NOT BE A CLIP. /design carries far more content than the
  // viewport — its canvas alone runs ~9× — so if the page stops scrolling and
  // nothing inside scrolls either, that content is simply unreachable.
  // Asserted on "some container inside .panels", NOT on .dv-flow-canvas by
  // name: which lens /design renders is session state that earlier sections
  // change, and a probe that hard-codes one lens' class reports a null and
  // blames the layout. The invariant is that the overflow moved INTO a panel,
  // not which element caught it.
  if (route === '/design') {
    check('the overflow moved into a panel, not off the page',
      r.inner >= 1 && r.tallest > 500, `${r.inner} inner scroller(s), tallest overflow ${r.tallest}px`);
  }
}

// And the release below 840px must be LIVE, not dead — the stacked layout
// hands scrolling BACK to the page (.mp-content gives up its own overflow
// down there), so a lock left on would clip whatever did not fit. A dead
// media rule is this file's recurring failure mode; assert the computed value.
for (const w of [839, 599]) {
  await p.setViewportSize({ width: w, height: 700 });
  await p.goto(BASE + '/intake', { waitUntil: 'networkidle' });
  const r = await p.evaluate(() => {
    const app = document.querySelector('#app');
    return { overflow: getComputedStyle(app).overflowY, minH: getComputedStyle(app).minHeight };
  });
  check(`@${w}px the page is the scroller again`, r.overflow === 'visible',
    `#app overflow-y=${r.overflow}`);
  check(`@${w}px the shell still fills the viewport`, parseFloat(r.minH) >= 699, `min-height=${r.minH}`);
}

console.log('\n=== L. the chip contract holds (D2) ===');
// THE BUG THIS CATCHES: .chip's box model (inline-flex, radius 999px, inset
// box-shadow border, never a real border) lives in ONE file, widgets.css —
// every one of the 11 migrated classes is now a thin tone hook that assumes
// that base is already on the element. If widgets.css stopped loading (link
// order regression, a typo'd href, base.html losing the tag), every chip on
// the page would silently fall back to browser defaults: an unstyled inline
// span with square corners and no border at all. Nothing throws; it just
// stops looking like a chip everywhere at once.
// Sections A-K run their whole sequence on the ONE shared page `p` — by the
// time L runs, that page's session/localStorage may carry selection state
// left over from earlier sections (e.g. G's "file read" picks a specific
// artifact), which changes what /design shows regardless of viewport. Use a
// fresh, isolated page so L always sees the same default /design view.
const lp = await b.newPage({ viewport: { width: 1400, height: 1000 } });
await lp.goto(BASE + '/design', { waitUntil: 'networkidle' });
const chipContract = () => [...document.querySelectorAll('.chip')].map((e) => {
  const cs = getComputedStyle(e);
  return { cls: e.className, display: cs.display, radius: cs.borderRadius, borderW: cs.borderWidth, shadow: cs.boxShadow };
});
const chips = await lp.evaluate(chipContract);
check('at least one .chip renders on /design', chips.length > 0, `found ${chips.length}`);
check('coverage: at least 20 .chip instances render (not a viewport fluke)', chips.length >= 20,
  `found only ${chips.length} — panels that carry chips may not be rendering at this viewport`);
// A .chip that is itself a flex/grid item gets its outer display "blockified"
// per the CSS Display spec — inline-flex resolves to flex in getComputedStyle
// even though the authored rule (and the actual box model) is inline-flex.
// That's expected here since nearly every chip sits inside a flex toolbar/row;
// accept both keywords as passing and rely on the radius/border/shadow checks
// below (plus the mutation test) to prove the box model is really from
// widgets.css and not a spec-mandated relabeling of a correctly-styled chip.
check('every .chip resolves to a flex box (inline-flex, blockified to flex when a flex/grid item)',
  chips.every((c) => c.display === 'inline-flex' || c.display === 'flex'),
  JSON.stringify(chips.filter((c) => c.display !== 'inline-flex' && c.display !== 'flex').map((c) => `${c.cls}=${c.display}`)));
check('every .chip is a full pill (radius: 999px)', chips.every((c) => c.radius === '999px'),
  JSON.stringify(chips.filter((c) => c.radius !== '999px').map((c) => `${c.cls}=${c.radius}`)));
check('no .chip carries a real border (inset box-shadow only)', chips.every((c) => c.borderW === '0px'),
  JSON.stringify(chips.filter((c) => c.borderW !== '0px').map((c) => `${c.cls}=${c.borderW}`)));

// MUTATION TEST: prove the checks above are actually exercising widgets.css
// and not just restating a browser default that would pass either way. Kill
// the stylesheet in-page and require the SAME assertion to flip to failing.
const killed = await lp.evaluate(() => {
  const link = [...document.querySelectorAll('link[rel=stylesheet]')].find((l) => l.href.includes('widgets.css'));
  if (!link) return false;
  link.disabled = true;
  return true;
});
if (!killed) {
  check('mutation test: widgets.css link found to disable', false, 'no <link> with widgets.css — cannot prove the check is live');
} else {
  const mutated = await lp.evaluate(chipContract);
  // radius/borderW alone are true for a bare unstyled span too (0 border,
  // browser-default radius can coincidentally read '0px'/'999px' is not one
  // of them, but don't rely on radius+border being sufficient on their own);
  // require the flex/inline-flex layout to also survive, since a plain span
  // reverts to display:inline the moment widgets.css stops applying.
  const stillPills = mutated.length > 0 && mutated.every((c) =>
    c.radius === '999px' && c.borderW === '0px' && (c.display === 'inline-flex' || c.display === 'flex'));
  check('mutation test: killing widgets.css breaks the pill contract (proves L is not vacuous)',
    !stillPills, stillPills ? 'chips STILL look like pills with widgets.css disabled — this section is not testing what it claims to' : 'confirmed: chips lost their box model');
}
await lp.close();

await b.close();
console.log(fails ? `\n==== ${fails} CHECK(S) FAILED ====` : '\n==== ALL CHECKS PASSED ====');
process.exit(fails ? 1 : 0);
