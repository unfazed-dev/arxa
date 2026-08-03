// probe-explode — the views explode lens, inter-flow hand-offs, and the two
// shell panels. Covers slices of
// docs/plans/views-explode-lens-interflow-and-shell-panels.md that the
// pre-existing probes do not touch.
//
// Dart port of `tools/probe-explode.mjs` (29 checks, 4 sections).
//
// Section B reaches into a tile's iframe from the parent through
// `contentDocument`, and that is deliberate rather than an oversight in the
// port: the read is one hop of a single expression that must ALSO click the
// list item and observe the outline the click paints on the in-frame element.
// Splitting it across an `evaluateInFrame` would put a round trip between the
// click and the read of its effect, which is the one thing this check cannot
// afford. The frame-scoped verbs exist for the cases the parent genuinely
// cannot answer — a pointer landing on a scaled tile, and a `window.parent`
// lookup that must resolve from inside — and neither is what this asks.

import 'dart:convert';

import 'package:appboxd/probes/probe_base.dart';

const Probe explodeProbe = Probe(
  name: 'explode',
  summary:
      'views explode lens, inter-flow hand-offs, and the two shell panels',
  // Reads and lens swaps only: the hand-off chip in section C continues a walk
  // through a GET, and nothing here POSTs into the served project.
  mutates: false,
  body: _run,
);

Future<void> _run(ProbeContext ctx) async {
  final page = await ctx.newPage(width: 1800, height: 1100);
  await ctx.goto(page, '/design');
  await probeWaitFor(
    page,
    "document.querySelectorAll('.dv-views-row').length > 0",
    timeout: const Duration(seconds: 15),
    label: 'the views lens rows',
    report: ctx.report,
  );

  ctx.report
      .section('A. views lens is rows of two columns (not the old single column)');
  final layout = _map(await page.evaluate('''
(() => {
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
})()'''));
  final counts = _map(layout['counts']);
  ctx.report.check('10 screen rows', layout['rows'] == 10, '${layout['rows']}');
  ctx.report.check('every row is 2 columns', layout['twoCols'] == true);
  ctx.report.check('portalo.auth explodes to 5 components',
      counts['portalo.auth'] == 5, '${counts['portalo.auth']}');
  ctx.report.check('portalo.account explodes to 9',
      counts['portalo.account'] == 9, '${counts['portalo.account']}');
  // splash/startup genuinely author zero [data-el]; an empty box would read as
  // a failure, so the empty STATE is the contract.
  ctx.report.check(
      'portalo.splash renders the empty state', layout['splashEmpty'] == true);
  ctx.report.check('portalo.startup renders the empty state',
      layout['startupEmpty'] == true);

  ctx.report.section('B. the three server joins + the live measurement');
  final detail = _map(await page.evaluate('''
(() => {
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
})()'''));
  final cont = _map(detail['cont']);
  ctx.report.check('labels resolved (not [object Object])',
      detail['labelsOk'] == true, jsonEncode(cont.keys.toList()));
  ctx.report.check('fires = the authored flow edge',
      cont['fires'] == 'Onboarding → portalo.home', '${cont['fires']}');
  ctx.report.check('kit = the declared registry kit', cont['kit'] == 'kit/auth',
      '${cont['kit']}');
  ctx.report.check(
      'box measured live, non-empty',
      RegExp(r'^\d+×\d+').hasMatch('${cont['box'] ?? ''}'),
      '${cont['box']}');
  ctx.report.check('fn from the rendered node',
      '${cont['function'] ?? ''}'.length > 10, '${cont['function']}');
  ctx.report.check(
      'clicking flashes the real element in the iframe',
      '${detail['outline']}'.contains('solid'),
      '${detail['outline']}');
  // THE ANTI-GUESS ASSERTION. field:Email has no authored edge and its label
  // does not match any trigger. If a future change loosens the fuzzy match,
  // this element will start claiming to fire something and this goes red.
  ctx.report.check('an element with no edge reads "—", never a guess',
      detail['emailFires'] == '—', '${detail['emailFires']}');

  ctx.report
      .section('C. inter-flow hand-offs (flows are joined by shared screen ids)');
  await page.evaluate("window.htmx.ajax('GET', '/design/viewer?mode=flows',"
      " { target: '#design-viewer', swap: 'morph:outerHTML' })");
  // The lens swap is an htmx morph; poll for the rows the counts are read from
  // rather than guessing how long the round-trip takes.
  await probeWaitFor(
    page,
    "document.querySelectorAll('.dv-flow-row').length >= 3",
    label: 'all three flow rows after the lens swap',
    report: ctx.report,
  );
  final ho = _map(await page.evaluate('Object.fromEntries('
      "[...document.querySelectorAll('.dv-flow-row')].map((r) => [r.dataset.flow, r.querySelectorAll('.dv-handoff').length]))"));
  // portalo.home ends Onboarding and heads BOTH browse-buy and account, so the
  // count is 2 — a single-valued hand-off would be a guess.
  ctx.report.check('flow-onboarding ends with 2 hand-off chips',
      ho['flow-onboarding'] == 2, jsonEncode(ho));
  ctx.report.check('flow-browse-buy has none (nothing continues from orders)',
      ho['flow-browse-buy'] == 0, '${ho['flow-browse-buy']}');
  ctx.report.check(
      'flow-account has none', ho['flow-account'] == 0, '${ho['flow-account']}');
  // D2's second axis made visible: a toast hangs off the TRANSITION, so the
  // chip must live on the connector, never on a tile. If it ever renders inside
  // .dv-tile the two axes have been re-merged and this goes red.
  final fb = _map(await page.evaluate('''
(() => ({
  onConnector: [...document.querySelectorAll('.dv-connector .dv-fb')].map((e) => e.className.replace('dv-fb dv-fb-', '') + ':' + e.textContent),
  onTile: document.querySelectorAll('.dv-tile .dv-fb').length,
}))()'''));
  final onConnector = (fb['onConnector'] as List? ?? const []);
  ctx.report.check('mutation edges show a feedback chip', onConnector.length == 2,
      jsonEncode(onConnector));
  ctx.report.check('feedback lives on the connector, never on a tile',
      fb['onTile'] == 0, '${fb['onTile']}');

  final jumped = _map(await page.evaluate('''
(async () => {
  document.querySelector('.dv-flow-row[data-flow="flow-onboarding"] .dv-handoff').click();
  await new Promise((r) => setTimeout(r, 1500));
  const w = document.querySelector('.dv-flow-row.is-walking, .dv-flow-row [data-id] .dv-tile.is-live');
  return { url: location.search, live: document.querySelector('.dv-tile.is-live')?.dataset.id ?? null, w: !!w };
})()'''));
  ctx.report.check('clicking a chip continues the walk in that flow',
      jumped['live'] == 'portalo.home', jsonEncode(jumped));

  ctx.report.section('D. the two shell panels survive fullscreen');
  await ctx.goto(page, '/design');
  await probeWaitFor(
    page,
    '''
(() => {
  const v = document.querySelector('.panel-viewer');
  return !!v && !!v.querySelector('.dv-topbar') && !!v.querySelector('.dv-botbar');
})()''',
    timeout: const Duration(seconds: 15),
    label: 'both shell panels',
    report: ctx.report,
  );
  final panels = _map(await page.evaluate('''
(() => {
  const v = document.querySelector('.panel-viewer');
  const inside = (s) => !!v.querySelector(s);
  return {
    topbar: inside('.dv-topbar'), botbar: inside('.dv-botbar'),
    miniDocked: inside('.dv-botbar .mini-panel'),
    miniStatic: getComputedStyle(v.querySelector('.mini-panel')).position === 'static',
    padBottom: getComputedStyle(v.querySelector('.dv-flow-canvas')).paddingBottom,
    // canvas.js fullscreens #design-viewer; anything outside it vanishes on
    // fullscreen, so these four MUST be inside or the user is stranded.
    lens: inside('.mini-panel-tab'), exit: inside('.dv-fs-close'),
    swatch: inside('.mini-swatch'), title: inside('.dv-topbar-title'),
    oldHead: !!document.querySelector('.artifact-head'),
  };
})()'''));
  ctx.report.check('top panel present', panels['topbar'] == true);
  ctx.report.check('bottom panel present', panels['botbar'] == true);
  ctx.report.check('mini panel is docked in the bottom panel',
      panels['miniDocked'] == true && panels['miniStatic'] == true);
  ctx.report.check('float-clearance hack deleted (padding-bottom != 11rem)',
      panels['padBottom'] != '176px', '${panels['padBottom']}');
  ctx.report
      .check('lens switch inside the fullscreen target', panels['lens'] == true);
  ctx.report.check(
      'fullscreen EXIT button inside the fullscreen target', panels['exit'] == true);
  ctx.report.check(
      'bg swatches inside the fullscreen target', panels['swatch'] == true);
  ctx.report.check('title inside the fullscreen target', panels['title'] == true);
  ctx.report.check('old artifact-head removed', panels['oldHead'] != true);

  ctx.report.check('no page errors', page.pageErrors.isEmpty,
      page.pageErrors.join(' | '));

  await ctx.closePage(page);
}

/// Narrow an `evaluate` result to a map.
///
/// Returns an empty map rather than throwing on null, so a section whose one
/// expression came back empty reports every check in it as failed with the
/// real values shown — the original's behaviour, where a missing key reads as
/// `undefined` and the check goes red rather than aborting the run.
Map<String, dynamic> _map(dynamic value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};
