// probe-reveal-drawer — every views-lens screen card carries a reveal-drawer
// tucked behind it (Screen Reveal-Drawer plan, increment 2).
//
// The drawer is the card's back panel: tucked it MUST be invisible without
// being absent (the trigger's aria-controls has to resolve, and a node minted
// on open would pop in instead of sliding out), and out it must sit beside the
// screen, translated on transform alone. Both end states are computed-style
// facts, so this probe reads getComputedStyle rather than class lists where
// the class would only be a proxy.
//
// Section A asserts the served shape: wrapper + drawer + hover-bar trigger per
// screen, everything tucked by default (D8: closed is the default view state),
// and the hover bar itself hidden until :hover/:focus-within — the same
// pure-CSS gate the other tile tools ride.
//
// Section B/D drive the toggle the way the island and htmx wire it (a click on
// the real <button>), then assert the a11y contract: aria-expanded tracks
// state, focus lands inside the panel on open and returns to the trigger on
// close (reveal.js), ESC closes.
//
// Section C is the tab skeleton: Composer is first-open and mounts the
// reusable composer with a drawer scope (zero id collisions with the panel
// instance); Tools/Logic render their honest placeholders.
//
// Section E is the reduced-motion instant path: with prefers-reduced-motion
// emulated the transition collapses to 0s — the swap is instant, not animated.

import 'package:appboxd/probes/probe_base.dart';

const Probe revealDrawerProbe = Probe(
  name: 'reveal-drawer',
  summary: 'screen cards reveal a tucked drawer: end states, a11y, tabs, reduced motion',
  // Opening the drawer / switching tabs writes session view state only (D8:
  // nothing persisted to project files). Nothing here survives the session.
  mutates: false,
  body: _run,
);

// The screen the end states are asserted on (portalo.auth): the slug is the
// id with dots CSS-escaped to dashes.
const _slug = 'portalo-auth';
const _drawerId = 'dv-drawer-$_slug';
const _drawerSel = '#$_drawerId';
const _triggerSel = '.dv-drawer-toggle[aria-controls="$_drawerId"]';

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

  ctx.report.section('A. served tucked: a drawer behind every card, hover bar gated');
  final served = _map(await page.evaluate('''
(() => {
  const rows = [...document.querySelectorAll('.dv-views-row')];
  const wraps = [...document.querySelectorAll('.dv-reveal')];
  const aside = document.querySelector('$_drawerSel');
  const trigger = document.querySelector('$_triggerSel');
  const tools = trigger && trigger.closest('.dv-tile-tools');
  const cs = aside && getComputedStyle(aside);
  const ids = [...document.querySelectorAll('[id]')].map((e) => e.id);
  const dupes = [...new Set(ids.filter((id, i) => ids.indexOf(id) !== i))];
  return {
    rows: rows.length,
    wraps: wraps.length,
    wrapPerRow: rows.every((r) => r.querySelector(':scope > .dv-reveal > .dv-tile')
        && r.querySelector(':scope > .dv-reveal > .dv-drawer')),
    allClosed: wraps.every((w) => !w.classList.contains('is-open')),
    allCollapsedAria: [...document.querySelectorAll('.dv-drawer-toggle')]
        .every((b) => b.tagName === 'BUTTON' && b.getAttribute('aria-expanded') === 'false'),
    tucked: cs ? { visibility: cs.visibility, transform: cs.transform } : null,
    toolsHidden: tools ? getComputedStyle(tools).opacity === '0' : null,
    dupes,
  };
})()'''));
  ctx.report
    ..check('a wrapper per views row', served['rows'] != null && served['rows'] == served['wraps'],
        '${served['wraps']} wrappers / ${served['rows']} rows')
    ..check('tile + drawer inside every wrapper', served['wrapPerRow'] == true)
    ..check('every drawer tucked by default (no .is-open)', served['allClosed'] == true)
    ..check('every trigger a real button with aria-expanded=false',
        served['allCollapsedAria'] == true)
    ..check('tucked end state: hidden, untranslated',
        served['tucked'] != null &&
            (served['tucked'] as Map)['visibility'] == 'hidden' &&
            ((served['tucked'] as Map)['transform'] == 'none' ||
                '${(served['tucked'] as Map)['transform']}'.endsWith(', 0, 0)')),
        '${served['tucked']}')
    ..check('hover bar hidden until hover/focus', served['toolsHidden'] == true)
    ..check('zero duplicate ids with every drawer composer mounted',
        (served['dupes'] as List?)?.isEmpty ?? false,
        (served['dupes'] as List?)?.take(6).join(', ') ?? '');

  ctx.report.section('B. trigger opens: out end state, aria, focus in the panel');
  // Synthetic click: the hover bar is opacity/pointer-events gated, and the
  // wiring under test is htmx's click listener + reveal.js, not the hover CSS
  // (section A already asserted the gate).
  await page.clickSelector(_triggerSel, synthetic: true);
  await probeWaitFor(
    page,
    "document.querySelector('$_triggerSel')?.getAttribute('aria-expanded') === 'true'",
    label: 'aria-expanded to flip true',
    report: ctx.report,
  );
  final open = _map(await page.evaluate('''
(() => {
  const aside = document.querySelector('$_drawerSel');
  const wrap = aside && aside.closest('.dv-reveal');
  const cs = aside && getComputedStyle(aside);
  const m = cs && cs.transform.match(/matrix\\(([^)]+)\\)/);
  const tx = m ? Number(m[1].split(',')[4]) : 0;
  const form = aside && aside.querySelector('form.composer');
  return {
    isOpen: wrap && wrap.classList.contains('is-open'),
    visibility: cs && cs.visibility,
    tx,
    focusInside: aside && aside.contains(document.activeElement),
    scope: form && form.dataset.composerScope,
    formId: form && form.id,
    panelComposer: !!document.getElementById('composer'),
  };
})()'''));
  ctx.report
    ..check('wrapper marked open', open['isOpen'] == true)
    ..check('out end state: visible', open['visibility'] == 'visible')
    ..check('out end state: translated beside the card (tx > 0)',
        (open['tx'] is num) && (open['tx'] as num) > 0, 'tx=${open['tx']}')
    ..check('focus moved into the panel', open['focusInside'] == true)
    ..check('Composer is the first-open tab, mounted with the drawer scope',
        open['scope'] == 'drawer-$_slug' && open['formId'] == 'composer--drawer-$_slug',
        'scope=${open['scope']} id=${open['formId']}')
    ..check('the composer panel instance still renders unscoped',
        open['panelComposer'] == true);

  ctx.report.section('C. tab skeleton: Tools/Logic placeholders, Composer returns');
  await page.clickSelector('#dv-drawer-tab-tools--$_slug', synthetic: true);
  await probeWaitFor(
    page,
    "document.querySelector('#dv-drawer-tab-tools--$_slug')?.getAttribute('aria-selected') === 'true'",
    label: 'the Tools tab to select',
    report: ctx.report,
  );
  final tools = _map(await page.evaluate('''
(() => {
  const aside = document.querySelector('$_drawerSel');
  const stub = aside && aside.querySelector('.dv-drawer-stub');
  return {
    stillOpen: !!(aside && aside.closest('.dv-reveal.is-open')),
    stub: stub ? stub.textContent.trim() : null,
    composerGone: !(aside && aside.querySelector('form.composer')),
  };
})()'''));
  ctx.report
    ..check('drawer stays out across the tab swap', tools['stillOpen'] == true)
    ..check('Tools renders its placeholder', tools['stub'] is String && (tools['stub'] as String).isNotEmpty,
        '${tools['stub']}')
    ..check('the composer unmounts with its tab', tools['composerGone'] == true);
  await page.clickSelector('#dv-drawer-tab-composer--$_slug', synthetic: true);
  await probeWaitFor(
    page,
    "!!document.querySelector('$_drawerSel form.composer')",
    label: 'the Composer tab to return',
    report: ctx.report,
  );
  ctx.report.check('Composer remounts on tab return',
      await page.evaluate("!!document.querySelector('$_drawerSel form.composer')") == true);

  ctx.report.section('D. ESC tucks the drawer away, focus returns to the trigger');
  await page.evaluate(
      "document.activeElement.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}))");
  await probeWaitFor(
    page,
    "document.querySelector('$_triggerSel')?.getAttribute('aria-expanded') === 'false'",
    label: 'aria-expanded to flip back',
    report: ctx.report,
  );
  // Visibility flips at transition END (D3): give the 0.28s transform its
  // delay-coupled visibility flip rather than reading mid-flight.
  await probeWaitFor(
    page,
    "getComputedStyle(document.querySelector('$_drawerSel')).visibility === 'hidden'",
    label: 'the tucked visibility flip at transition end',
    report: ctx.report,
  );
  final closed = _map(await page.evaluate('''
(() => {
  const aside = document.querySelector('$_drawerSel');
  const trigger = document.querySelector('$_triggerSel');
  return {
    tucked: !!(aside && !aside.closest('.dv-reveal').classList.contains('is-open')),
    visibility: aside && getComputedStyle(aside).visibility,
    focusOnTrigger: document.activeElement === trigger,
  };
})()'''));
  ctx.report
    ..check('ESC tucks the drawer', closed['tucked'] == true)
    ..check('tucked end state hidden again', closed['visibility'] == 'hidden')
    ..check('focus returned to the trigger', closed['focusOnTrigger'] == true);

  ctx.report.section('E. prefers-reduced-motion: the instant path');
  await page.send('Emulation.setEmulatedMedia', {
    'features': [
      {'name': 'prefers-reduced-motion', 'value': 'reduce'},
    ],
  });
  final reduced = _map(await page.evaluate('''
(() => {
  const cs = getComputedStyle(document.querySelector('$_drawerSel'));
  return { duration: cs.transitionDuration, property: cs.transitionProperty };
})()'''));
  ctx.report.check('transition collapses to 0s under reduced motion',
      '${reduced['duration']}'.split(',').every((d) => d.trim() == '0s'),
      '${reduced['duration']} on ${reduced['property']}');
  await page.clickSelector(_triggerSel, synthetic: true);
  await probeWaitFor(
    page,
    "document.querySelector('$_triggerSel')?.getAttribute('aria-expanded') === 'true'",
    label: 'the reduced-motion open',
    report: ctx.report,
  );
  ctx.report.check('instant swap: visible the moment the state lands',
      await page.evaluate(
              "getComputedStyle(document.querySelector('$_drawerSel')).visibility") ==
          'visible');

  ctx.report.section('F. qps-ploc: pseudo-expanded strings fit the drawer chrome (D9)');
  // Read on the INITIAL render, no swaps: the drawer (tabs + first-open
  // Composer tab) is server-rendered even tucked, and a swap would re-render
  // in en anyway — the ?lang= param does not ride the drawer's own GETs.
  await ctx.goto(page, '/design?lang=qps-ploc');
  await probeWaitFor(
    page,
    "document.querySelectorAll('.dv-reveal').length > 0",
    timeout: const Duration(seconds: 15),
    label: 'the qps-ploc render',
    report: ctx.report,
  );
  final ploc = _map(await page.evaluate('''
(() => {
  const aside = document.querySelector('$_drawerSel');
  const tabs = [...aside.querySelectorAll('.dv-drawer-tab')];
  const ar = aside.getBoundingClientRect();
  const body = aside.querySelector('.dv-drawer-body');
  return {
    lang: document.documentElement.lang,
    nTabs: tabs.length,
    tabsFit: tabs.every((t) => {
      const r = t.getBoundingClientRect();
      return r.width > 0 && r.right <= ar.right + 1 && r.left >= ar.left - 1;
    }),
    scrollFits: aside.scrollWidth <= aside.clientWidth + 1,
    bodyFits: body.scrollWidth <= body.clientWidth + 1,
  };
})()'''));
  ctx.report
    // The locale guard first: without it the three fits below would pass on
    // the EN render and the section would assert nothing.
    ..check('the page is actually qps-ploc', ploc['lang'] == 'qps-ploc',
        '${ploc['lang']}')
    ..check('all three tabs render', ploc['nTabs'] == 3, '${ploc['nTabs']}')
    ..check('pseudo-expanded tab labels stay inside the drawer',
        ploc['tabsFit'] == true)
    ..check('no horizontal overflow in the drawer chrome',
        ploc['scrollFits'] == true)
    ..check('no horizontal overflow in the drawer body',
        ploc['bodyFits'] == true);

  ctx.report.check('no page errors', page.pageErrors.isEmpty,
      page.pageErrors.join(' | '));

  await ctx.closePage(page);
}

/// Narrow an `evaluate` result to a map. Same contract as the other studio
/// probes: an empty map fails every check in the section with the real values
/// shown, rather than aborting the run.
Map<String, dynamic> _map(dynamic value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};
