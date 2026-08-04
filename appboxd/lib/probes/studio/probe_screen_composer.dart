// probe-screen-composer — the per-screen edit composer's scope placeholder
// tracks the widget selection.
//
// The composer states what a submission will touch BEFORE the user types
// (decision 8). The widget editor swaps into `#dv-wedit-<slot>` alone, so
// nothing in that exchange re-renders the composer sitting beside it: without
// the composer's own hx-get the placeholder keeps saying "applies to this
// screen" while a component is selected, and the user commits a screen-wide
// intent believing it was scoped to the widget. That is a silent wrong write,
// not a cosmetic lag, which is why it gets a probe.
//
// Section A asserts the wiring exists in the served HTML — every composer's
// `from:` selector must name a container that is actually on the page. A
// trigger bound to a selector that matches nothing is invisible: no error, no
// request, and section B would be the only thing that ever noticed.
//
// Section B is the behaviour, driven the way a user drives it (a click on an
// explode row, not a synthesised POST), because the click is what proves the
// island's target and the composer's trigger agree.

import 'dart:convert';

import 'package:appboxd/probes/probe_base.dart';

const Probe screenComposerProbe = Probe(
  name: 'screen-composer',
  summary: "per-screen composer's scope placeholder follows the widget selection",
  // Selecting a widget writes session state (`d.widgetSel`) and no project
  // file — the editor reads the source, and this probe never posts an attr
  // change or an intent. Nothing here survives the session.
  mutates: false,
  body: _run,
);

// The screen the flip is asserted on: `auth.html` carries real `data-el`
// widgets. Splash and startup have none, so their explode rows are empty and a
// click there would prove nothing.
const _screen = 'portalo.auth';
const _slot = 'portalo-auth';

// A second screen with real widgets, for the selection-moved case in section C.
const _second = 'portalo.home';
const _secondSlot = 'portalo-home';

Future<void> _run(ProbeContext ctx) async {
  final page = await ctx.newPage(width: 1800, height: 1100);
  await ctx.goto(page, '/design');
  await probeWaitFor(
    page,
    "document.querySelectorAll('.dv-compose').length > 0",
    timeout: const Duration(seconds: 15),
    label: 'the per-screen composers',
    report: ctx.report,
  );

  ctx.report.section('A. every composer asks for itself, from a node that exists');
  final wiring = _map(await page.evaluate('''
(() => {
  const composers = [...document.querySelectorAll('.dv-compose')];
  const dangling = composers
    .map((c) => (c.getAttribute('hx-trigger') || '').match(/from:#([^\\s"]+)/))
    .filter((m) => m && !document.getElementById(m[1]))
    .map((m) => m[1]);
  return {
    n: composers.length,
    // Self-targeted: the fragment replaces the composer, not the panels tree.
    selfTargeted: composers.every((c) => c.getAttribute('hx-target') === 'this'
        && (c.getAttribute('hx-get') || '').includes('/design/screen/composer')),
    dangling: dangling,
    // Every composer starts screen-scoped: nothing is selected on first paint.
    allScreenScoped: composers.every((c) => c.dataset.composeScope === 'screen'),
  };
})()'''));
  ctx.report
    ..check('a composer per screen', wiring['n'] == 10, '${wiring['n']}')
    ..check('each composer re-fetches itself', wiring['selfTargeted'] == true)
    ..check('no trigger names a missing container',
        (wiring['dangling'] as List?)?.isEmpty ?? false,
        jsonEncode(wiring['dangling']))
    ..check('all screen-scoped before any selection',
        wiring['allScreenScoped'] == true);

  ctx.report.section('B. selecting a widget re-scopes that composer, and only it');
  final before = _map(await page.evaluate('''
(() => {
  // Survives the swaps that follow; a full navigation would clear it.
  window.__composerProbe = 'alive';
  const c = document.getElementById('dv-compose-$_slot');
  const other = document.querySelector('.dv-compose:not(#dv-compose-$_slot)');
  const row = document.querySelector('[data-explode-row="$_screen"] .dv-explode-el');
  if (row) row.click();
  return {
    clicked: !!row,
    scope: c && c.dataset.composeScope,
    otherId: other && other.id,
    otherScope: other && other.dataset.composeScope,
  };
})()'''));
  ctx.report.check('an explode row to click on $_screen', before['clicked'] == true);
  ctx.report.check(
      '$_screen starts screen-scoped', before['scope'] == 'screen', '${before['scope']}');

  // The composer is replaced by its own fragment: re-query by id, never hold
  // the old node. The wait is the assertion — a timeout here IS the stale
  // placeholder this probe exists to catch.
  await probeWaitFor(
    page,
    "document.getElementById('dv-compose-$_slot')"
    "?.dataset.composeScope === 'widget'",
    timeout: const Duration(seconds: 10),
    label: 'the composer re-scoping to the selected widget',
    report: ctx.report,
  );

  final after = _map(await page.evaluate('''
(() => {
  const c = document.getElementById('dv-compose-$_slot');
  const others = [...document.querySelectorAll('.dv-compose')]
    .filter((n) => n.id !== 'dv-compose-$_slot');
  const input = c && c.querySelector('.dv-compose-input');
  return {
    scope: c && c.dataset.composeScope,
    screens: c && c.dataset.composeScreens,
    placeholder: input && input.getAttribute('placeholder'),
    weditFilled: !!document.querySelector('#dv-wedit-$_slot .wed-pane, #dv-wedit-$_slot *'),
    othersStillScreen: others.every((n) => n.dataset.composeScope === 'screen'),
    noReload: window.__composerProbe === 'alive',
    // The composer that came back must still carry its own trigger, or the
    // next selection is the stale one.
    rearmed: c && (c.getAttribute('hx-trigger') || '').includes('from:#dv-wedit-$_slot'),
  };
})()'''));
  ctx.report
    ..check('composer is widget-scoped after the click', after['scope'] == 'widget',
        '${after['scope']}')
    ..check('placeholder names the widget, not the screen',
        after['placeholder'] is String &&
            !(after['placeholder'] as String).contains(_screen),
        '${after['placeholder']}')
    ..check('provenance count is stated', after['screens'] != '0', '${after['screens']}')
    ..check('the widget editor did land beside it', after['weditFilled'] == true)
    ..check('every other composer stays screen-scoped',
        after['othersStillScreen'] == true)
    ..check('no page reload', after['noReload'] == true)
    ..check('the replacement composer is re-armed', after['rearmed'] == true);

  ctx.report.section('C. moving the selection to another screen un-scopes the first');
  // The inverse of section B, and the one the per-slot trigger cannot see on
  // its own: this click settles #dv-wedit-<other>, so nothing about the
  // exchange touches the composer we just scoped. If it stays widget-scoped it
  // is lying in the other direction — offering "applies to <widget>" for a
  // widget that is no longer selected, which submits a widget-scoped intent
  // the user did not choose.
  final moved = _map(await page.evaluate('''
(() => {
  const row = document.querySelector('[data-explode-row="$_second"] .dv-explode-el');
  if (row) row.click();
  return { clicked: !!row };
})()'''));
  ctx.report.check('an explode row to click on $_second', moved['clicked'] == true);

  await probeWaitFor(
    page,
    "document.getElementById('dv-compose-$_secondSlot')"
    "?.dataset.composeScope === 'widget'",
    timeout: const Duration(seconds: 10),
    label: 'the second screen taking the selection',
    report: ctx.report,
  );

  final unscoped = _map(await page.evaluate('''
(() => {
  const first = document.getElementById('dv-compose-$_slot');
  const input = first && first.querySelector('.dv-compose-input');
  return {
    scope: first && first.dataset.composeScope,
    placeholder: input && input.getAttribute('placeholder'),
    widgetScoped: [...document.querySelectorAll('.dv-compose')]
      .filter((n) => n.dataset.composeScope === 'widget').map((n) => n.id),
    noReload: window.__composerProbe === 'alive',
  };
})()'''));
  ctx.report
    ..check('the first composer is screen-scoped again',
        unscoped['scope'] == 'screen', '${unscoped['scope']}')
    ..check('its placeholder stops naming the old widget',
        unscoped['placeholder'] is String &&
            (unscoped['placeholder'] as String).contains(_screen),
        '${unscoped['placeholder']}')
    ..check('exactly one composer is widget-scoped',
        (unscoped['widgetScoped'] as List?)?.length == 1,
        jsonEncode(unscoped['widgetScoped']))
    ..check('still no page reload', unscoped['noReload'] == true);

  ctx.report.check('no page errors', page.pageErrors.isEmpty,
      page.pageErrors.join(' | '));

  await ctx.closePage(page);
}

/// Narrow an `evaluate` result to a map. Same contract as the other studio
/// probes: an empty map fails every check in the section with the real values
/// shown, rather than aborting the run.
Map<String, dynamic> _map(dynamic value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};
