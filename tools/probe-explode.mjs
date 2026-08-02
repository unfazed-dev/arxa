// probe-explode.mjs — the views explode lens, inter-flow hand-offs, and the two shell panels.
// Covers the three slices of docs/plans/views-explode-lens-interflow-and-shell-panels.md
// that the pre-existing probes do not touch at all.
// Run against a live studio:
//   dart run appboxd/bin/appbox.dart design serve designs/appbox-studio --port 4319 --json --project portalo
//   node tools/probe-explode.mjs
// Override with APPBOX_BASE / APPBOX_CHROME.
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { chromium } = await import(
  path.join(REPO, 'skills/appbox-designer/runtime/node_modules/playwright-core/index.mjs'));
const CHROME = process.env.APPBOX_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
import { resolveBase, waitFor, trackTransitions } from './_probe_base.mjs';
const BASE = resolveBase();
let b, fails = 0;
const check = (n, ok, x = '') => { if (!ok) fails++; console.log(`  [${ok ? 'PASS' : 'FAIL'}] ${n}${x ? ' — ' + x : ''}`); };

try {
  b = await chromium.launch({ executablePath: CHROME, headless: true });
  const p = await b.newPage({ viewport: { width: 1800, height: 1100 } });
  await trackTransitions(p);
  const pageErrors = [];
  p.on('pageerror', (e) => pageErrors.push(e.message));
  await p.goto(BASE + '/design', { waitUntil: 'networkidle' });
  await waitFor(p, () => document.querySelectorAll('.dv-views-row').length > 0,
    { label: 'the views lens rows', timeout: 15000 });

  console.log('=== A. views lens is rows of two columns (not the old single column) ===');
  const layout = await p.evaluate(() => {
    const rows = [...document.querySelectorAll('.dv-views-row')];
    return {
      rows: rows.length,
      // The bug this replaced: .dv-flow-canvas .dv-zoom (0,2,0) beat
      // .dv-zoom-views (0,1,0) on flex-direction, so every tile got its own
      // line. Assert real geometry, not the declared rule.
      twoCols: rows.every((r) => getComputedStyle(r).gridTemplateColumns.split(' ').length === 2),
      counts: Object.fromEntries(rows.map((r) => [r.dataset.explodeRow, r.querySelectorAll('.dv-explode-el').length])),
      splashEmpty: !!document.querySelector('[data-explode-row="portalo.splash"] .dv-explode-empty'),
      startupEmpty: !!document.querySelector('[data-explode-row="portalo.startup"] .dv-explode-empty'),
    };
  });
  check('10 screen rows', layout.rows === 10, String(layout.rows));
  check('every row is 2 columns', layout.twoCols);
  check('portalo.auth explodes to 5 components', layout.counts['portalo.auth'] === 5, String(layout.counts['portalo.auth']));
  check('portalo.account explodes to 9', layout.counts['portalo.account'] === 9, String(layout.counts['portalo.account']));
  // splash/startup genuinely author zero [data-el]; an empty box would read as
  // a failure, so the empty STATE is the contract.
  check('portalo.splash renders the empty state', layout.splashEmpty);
  check('portalo.startup renders the empty state', layout.startupEmpty);

  console.log('\n=== B. the three server joins + the live measurement ===');
  const detail = await p.evaluate(() => {
    const row = document.querySelector('[data-explode-row="portalo.auth"]');
    const pick = (name) => [...row.querySelectorAll('.dv-explode-el')]
      .find((e) => e.querySelector('b').textContent === name);
    const read = (li) => {
      li.click();
      const dt = [...li.querySelectorAll('.dv-explode-detail dt')].map((x) => x.textContent);
      const dd = [...li.querySelectorAll('.dv-explode-detail dd')].map((x) => x.textContent);
      return Object.fromEntries(dt.map((k, i) => [k, dd[i]]));
    };
    const cont = read(pick('button:Continue'));
    const outline = row.querySelector('iframe').contentDocument
      .querySelector('[data-el="button:Continue"]').style.outline;
    const email = read(pick('field:Email'));
    return { cont, outline, emailFires: email.fires, labelsOk: !JSON.stringify(cont).includes('object Object') };
  });
  check('labels resolved (not [object Object])', detail.labelsOk, JSON.stringify(Object.keys(detail.cont)));
  check('fires = the authored flow edge', detail.cont.fires === 'Onboarding → portalo.home', detail.cont.fires);
  check('kit = the declared registry kit', detail.cont.kit === 'kit/auth', detail.cont.kit);
  check('box measured live, non-empty', /^\d+×\d+/.test(detail.cont.box || ''), detail.cont.box);
  check('fn from the rendered node', (detail.cont.function || '').length > 10, detail.cont.function);
  check('clicking flashes the real element in the iframe', detail.outline.includes('solid'), detail.outline);
  // THE ANTI-GUESS ASSERTION. field:Email has no authored edge and its label
  // does not match any trigger. If a future change loosens the fuzzy match,
  // this element will start claiming to fire something and this goes red.
  check('an element with no edge reads "—", never a guess', detail.emailFires === '—', detail.emailFires);

  console.log('\n=== C. inter-flow hand-offs (flows are joined by shared screen ids) ===');
  await p.evaluate((u) => window.htmx.ajax('GET', u, { target: '#design-viewer', swap: 'morph:outerHTML' }), '/design/viewer?mode=flows');
  // The lens swap is an htmx morph; poll for the rows the counts are read from
  // rather than guessing how long the round-trip takes.
  await waitFor(p, () => document.querySelectorAll('.dv-flow-row').length >= 3,
    { label: 'all three flow rows after the lens swap' });
  const ho = await p.evaluate(() => Object.fromEntries(
    [...document.querySelectorAll('.dv-flow-row')].map((r) => [r.dataset.flow, r.querySelectorAll('.dv-handoff').length])));
  // portalo.home ends Onboarding and heads BOTH browse-buy and account, so the
  // count is 2 — a single-valued hand-off would be a guess.
  check('flow-onboarding ends with 2 hand-off chips', ho['flow-onboarding'] === 2, JSON.stringify(ho));
  check('flow-browse-buy has none (nothing continues from orders)', ho['flow-browse-buy'] === 0, String(ho['flow-browse-buy']));
  check('flow-account has none', ho['flow-account'] === 0, String(ho['flow-account']));
  // D2's second axis made visible: a toast hangs off the TRANSITION, so the
  // chip must live on the connector, never on a tile. If it ever renders inside
  // .dv-tile the two axes have been re-merged and this goes red.
  const fb = await p.evaluate(() => ({
    onConnector: [...document.querySelectorAll('.dv-connector .dv-fb')].map((e) => e.className.replace('dv-fb dv-fb-', '') + ':' + e.textContent),
    onTile: document.querySelectorAll('.dv-tile .dv-fb').length,
  }));
  check('mutation edges show a feedback chip', fb.onConnector.length === 2, JSON.stringify(fb.onConnector));
  check('feedback lives on the connector, never on a tile', fb.onTile === 0, String(fb.onTile));

  const jumped = await p.evaluate(async () => {
    document.querySelector('.dv-flow-row[data-flow="flow-onboarding"] .dv-handoff').click();
    await new Promise((r) => setTimeout(r, 1500));
    const w = document.querySelector('.dv-flow-row.is-walking, .dv-flow-row [data-id] .dv-tile.is-live');
    return { url: location.search, live: document.querySelector('.dv-tile.is-live')?.dataset.id ?? null, w: !!w };
  });
  check('clicking a chip continues the walk in that flow', jumped.live === 'portalo.home', JSON.stringify(jumped));

  console.log('\n=== D. the two shell panels survive fullscreen ===');
  await p.goto(BASE + '/design', { waitUntil: 'networkidle' });
  await waitFor(p, () => {
    const v = document.querySelector('.design-viewer');
    return !!v && !!v.querySelector('.dv-topbar') && !!v.querySelector('.dv-botbar');
  }, { label: 'both shell panels', timeout: 15000 });
  const panels = await p.evaluate(() => {
    const v = document.querySelector('.design-viewer');
    const inside = (s) => !!v.querySelector(s);
    return {
      topbar: inside('.dv-topbar'), botbar: inside('.dv-botbar'),
      miniDocked: inside('.dv-botbar .mini-panel'),
      miniStatic: getComputedStyle(v.querySelector('.mini-panel')).position === 'static',
      padBottom: getComputedStyle(v.querySelector('.dv-flow-canvas')).paddingBottom,
      // canvas.js fullscreens .design-viewer; anything outside it vanishes on
      // fullscreen, so these four MUST be inside or the user is stranded.
      lens: inside('.mini-panel-tab'), exit: inside('.dv-fs-close'),
      swatch: inside('.mini-swatch'), title: inside('.dv-topbar-title'),
      oldHead: !!document.querySelector('.artifact-head'),
    };
  });
  check('top panel present', panels.topbar);
  check('bottom panel present', panels.botbar);
  check('mini panel is docked in the bottom panel', panels.miniDocked && panels.miniStatic);
  check('float-clearance hack deleted (padding-bottom != 11rem)', panels.padBottom !== '176px', panels.padBottom);
  check('lens switch inside the fullscreen target', panels.lens);
  check('fullscreen EXIT button inside the fullscreen target', panels.exit);
  check('bg swatches inside the fullscreen target', panels.swatch);
  check('title inside the fullscreen target', panels.title);
  check('old artifact-head removed', !panels.oldHead);

  check('no page errors', pageErrors.length === 0, pageErrors.join(' | '));
} catch (e) { console.log('PROBE ERROR:', e.message); fails++; }
finally { if (b) await b.close(); console.log(`\n==== ${fails ? fails + ' FAILED' : 'ALL CHECKS PASSED'} ====`); }
