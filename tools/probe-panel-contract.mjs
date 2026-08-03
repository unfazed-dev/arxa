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
await p.setViewportSize({ width: 1900, height: 1000 });

await b.close();
console.log(fails ? `\n==== ${fails} CHECK(S) FAILED ====` : '\n==== ALL CHECKS PASSED ====');
process.exit(fails ? 1 : 0);
