// probe-widget-logic — the drawer's Logic tab renders the deterministic
// connection graph (Screen Reveal-Drawer plan, increment 4, D6).
//
// D6's claim under test is PROVENANCE, not presence: every edge the pane
// shows is derived from repo facts (registry route/comp/kits, flows' authored
// `element` joins, the source element's data-inspect annotations) and renders
// in BOTH phrasings — a technical line (ids, nav op, flow id) and a plain
// sentence — from the SAME fact. Section B pins the one widget portalo wires
// by name (button:Continue → portalo.home in flow-onboarding) and asserts both
// renderings of that single edge.
//
// The counter-claim matters as much: what static analysis cannot derive must
// render an honest state and NEVER a fabricated edge. Section C walks every
// widget row on the screen and asserts the fabrication-free shape — the
// unwired card admits no edge names it (and shows no target id), the two
// templated buttons admit their data-el is unresolvable, and every row
// carries exactly one wiring state.
//
// Section D is D5 singularity again: a selection made in the Tools tab marks
// the same widget's row here — one shared d.widgetSel, no parallel mechanism.

import 'package:arxa/probes/probe_base.dart';

const Probe widgetLogicProbe = Probe(
  name: 'widget-logic',
  summary: 'Logic tab: deterministic graph, dual phrasing, honest-unknown fallback',
  // View state only (D8): the probe selects a widget and flips tabs, both
  // session-scoped; no control here writes a project file.
  mutates: false,
  body: _run,
);

// Same screen pick as probe-reveal-drawer / probe-widget-tools.
const _slug = 'portalo-auth';
const _drawerSel = '#dv-drawer-$_slug';
const _triggerSel = '.dv-drawer-toggle[aria-controls="dv-drawer-$_slug"]';
const _logicTabSel = '#dv-drawer-tab-logic--$_slug';

Future<void> _run(ProbeContext ctx) async {
  final page = await ctx.newPage(width: 1800, height: 1100);
  await ctx.goto(page, '/design');
  await probeWaitFor(
    page,
    "document.querySelectorAll('.dv-reveal').length > 0",
    timeout: const Duration(seconds: 15),
    label: 'the reveal-drawer wrappers',
    report: ctx.report,
  );
  await page.clickSelector(_triggerSel, synthetic: true);
  await probeWaitFor(
    page,
    "document.querySelector('$_triggerSel')?.getAttribute('aria-expanded') === 'true'",
    label: 'the drawer to open',
    report: ctx.report,
  );
  await page.clickSelector(_logicTabSel, synthetic: true);
  await probeWaitFor(
    page,
    "!!document.querySelector('$_drawerSel .dv-logic')",
    label: 'the Logic pane',
    report: ctx.report,
  );

  ctx.report.section('A. screen wiring from the registry, technical + plain');
  final screen = _map(await page.evaluate('''
(() => {
  const aside = document.querySelector('$_drawerSel');
  const facts = [...aside.querySelectorAll('.dv-logic-fact')].map((f) => f.textContent.trim());
  return {
    facts: facts.join(' | '),
    plain: aside.querySelector('.dv-logic-screen > .dv-logic-plain')?.textContent.trim() ?? null,
    widgetRows: aside.querySelectorAll('.dv-logic-widget').length,
  };
})()'''));
  ctx.report
    ..check('route renders from the registry entry',
        (screen['facts'] as String? ?? '').contains('/auth'), '${screen['facts']}')
    ..check('build class renders from the registry entry',
        (screen['facts'] as String? ?? '').contains('PortaloAuth'))
    ..check('declared kit renders', (screen['facts'] as String? ?? '').contains('kit/auth'))
    ..check('the plain screen sentence renders over the same facts',
        screen['plain'] is String && (screen['plain'] as String).contains('/auth'),
        '${screen['plain']}')
    ..check('one row per addressable widget (card, field, 3 buttons)',
        screen['widgetRows'] == 5, '${screen['widgetRows']}');

  ctx.report.section('B. known widget: one edge, both phrasings, same fact');
  final known = _map(await page.evaluate('''
(() => {
  const rows = [...document.querySelectorAll('$_drawerSel .dv-logic-widget')];
  const row = rows.find((r) => r.querySelector('.dv-logic-widget-head code')?.textContent.trim() === 'button:Continue');
  if (!row) return {};
  return {
    wiring: row.dataset.wiring,
    tech: row.querySelector('.dv-logic-edge .dv-logic-tech')?.textContent.trim() ?? null,
    plain: row.querySelector('.dv-logic-edge .dv-logic-plain')?.textContent.trim() ?? null,
    fn: row.querySelector('.dv-logic-fn .dv-logic-plain')?.textContent.trim() ?? null,
  };
})()'''));
  final tech = known['tech'] as String? ?? '';
  final plain = known['plain'] as String? ?? '';
  ctx.report
    ..check('the row resolves to an authored edge', known['wiring'] == 'edge',
        'wiring=${known['wiring']}')
    ..check('technical phrasing names target, nav op and flow id',
        tech.contains('portalo.home') && tech.contains('push') && tech.contains('flow-onboarding'),
        tech)
    ..check('plain phrasing names the same target and flow in words',
        plain.contains('Home') && plain.contains('Onboarding'), plain)
    ..check('the declared function renders from data-inspect-fn',
        (known['fn'] as String? ?? '').contains('Continues to the home screen'),
        'fn=${known['fn']}');

  ctx.report.section('C. honesty: unwired and unknown states, never a fabricated edge');
  final honest = _map(await page.evaluate('''
(() => {
  const rows = [...document.querySelectorAll('$_drawerSel .dv-logic-widget')];
  const card = rows.find((r) => r.querySelector('.dv-logic-widget-head code')?.textContent.trim() === 'card:Sign in');
  const states = rows.map((r) => r.dataset.wiring ?? 'missing');
  const oneEdgeBlock = rows.every((r) => r.querySelectorAll('.dv-logic-edge').length === 1);
  const allPlain = rows.every((r) => (r.querySelector('.dv-logic-edge .dv-logic-plain')?.textContent.trim() ?? '') !== '');
  return {
    cardWiring: card?.dataset.wiring ?? null,
    cardText: card?.textContent ?? '',
    states: states.join(','),
    known: states.filter((s) => s === 'edge').length,
    unwired: states.filter((s) => s === 'unwired').length,
    unknown: states.filter((s) => s === 'unknown').length,
    oneEdgeBlock,
    allPlain,
  };
})()'''));
  ctx.report
    ..check('the unwired card says so', honest['cardWiring'] == 'unwired',
        'wiring=${honest['cardWiring']}')
    ..check('the unwired row fabricates no target (no screen id leaks in)',
        !(honest['cardText'] as String? ?? '').contains('portalo.'),
        'text=${(honest['cardText'] as String? ?? '').substring(0, 80)}')
    ..check('exactly one wired widget (the Continue button)', honest['known'] == 1,
        '${honest['states']}')
    ..check('static unwired rows: card + email field', honest['unwired'] == 2,
        '${honest['states']}')
    ..check('templated names render unknown, not a guess (Apple/Google buttons)',
        honest['unknown'] == 2, '${honest['states']}')
    ..check('every row renders exactly one wiring block', honest['oneEdgeBlock'] == true)
    ..check('every wiring block carries a plain sentence', honest['allPlain'] == true);

  ctx.report.section('D. the Tools selection marks the same row here (one shared state)');
  await page.clickSelector('#dv-drawer-tab-tools--$_slug', synthetic: true);
  await probeWaitFor(
    page,
    "!!document.querySelector('$_drawerSel .dv-tools')",
    label: 'the Tools pane',
    report: ctx.report,
  );
  await page.clickSelector('$_drawerSel .dv-tools-sib', synthetic: true);
  await probeWaitFor(
    page,
    "!!document.querySelector('$_drawerSel .dv-tools-sib.on')",
    label: 'the strip pick to land',
    report: ctx.report,
  );
  await page.clickSelector(_logicTabSel, synthetic: true);
  await probeWaitFor(
    page,
    "!!document.querySelector('$_drawerSel .dv-logic-widget.on')",
    label: 'the Logic pane to mark the selection',
    report: ctx.report,
  );
  final marked = _map(await page.evaluate('''
(() => {
  const on = document.querySelector('$_drawerSel .dv-logic-widget.on');
  return {
    head: on?.querySelector('.dv-logic-widget-head code')?.textContent.trim() ?? null,
    current: on?.getAttribute('aria-current') ?? null,
    count: document.querySelectorAll('$_drawerSel .dv-logic-widget.on').length,
  };
})()'''));
  ctx.report
    ..check('the widget picked in Tools is the marked row (card, the first strip pick)',
        marked['head'] == 'card:Sign in', '${marked['head']}')
    ..check('exactly one row marked, exposed via aria-current',
        marked['count'] == 1 && marked['current'] == 'true',
        'count=${marked['count']} current=${marked['current']}');

  ctx.report.section('E. no duplicate ids with the Logic pane mounted');
  final dupes = await page.evaluate('''
(() => {
  const seen = new Set(); const dup = [];
  document.querySelectorAll('[id]').forEach((n) => { if (seen.has(n.id)) dup.push(n.id); seen.add(n.id); });
  return dup;
})()''');
  ctx.report.check('zero duplicate ids on the page',
      dupes is List && dupes.isEmpty, '$dupes');

  ctx.report.check('no page errors', page.pageErrors.isEmpty,
      page.pageErrors.join(' | '));

  await ctx.closePage(page);
}

/// Narrow an `evaluate` result to a map — same contract as the other studio
/// probes: an empty map fails every check with real values shown.
Map<String, dynamic> _map(dynamic value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};
