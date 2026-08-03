// probe-flowwalk — the flow walk: tap a flow edge's element INSIDE a tile's
// iframe and watch the parent row's active tile advance, without the grid being
// rebuilt.
//
// This is the check the design selftest structurally cannot make. "every
// hx-target names an element that exists" and "every GET route answers 200"
// both pass just as happily on a toolbar with the wrong tools in it and on a
// walk that never moves — they are structural, not behavioural. The two things
// that actually matter here only exist at runtime, in a browser, across an
// iframe boundary:
//
//   1. the views lens does NOT offer an interactive mode (its destination would
//      come from nextEdge with no flow to scope it, i.e. a guess), and
//   2. a tap inside the walked tile moves the PARENT row, keeps the tile
//      showing the screen it is labelled with, and does not destroy the grid.
//
// Dart port of `tools/probe-flowwalk.mjs` (14 checks, 5 sections).
//
// One deliberate divergence from the original, in output rather than in what
// is asserted: the trailer is the harness's (`==== ALL PASSED ====`), not this
// probe's own `ALL CHECKS PASSED`. One suite needs one scannable closing line,
// or `probe all` ends with a different trailer per probe.
//
// The verdict shape itself is NOT a divergence. This probe's original prints a
// bare `PASS`/`FAIL` where every other one prints `[PASS]`/`[FAIL]`, and the
// harness reproduces that from `bareVerdicts: true` below. It is a flag rather
// than this file writing to the report's sink because `check()` is the only
// path to the failure count: bare lines written directly would print `FAIL` and
// still exit 0, which is the one outcome a probe suite must never produce.

import 'dart:convert';

import 'package:appboxd/cdp.dart';
import 'package:appboxd/probes/probe_base.dart';

const String _flow = 'flow-onboarding';
const String _from = 'portalo.auth'; // the screen with the Continue button
const String _to = 'portalo.home'; // where the "continue" edge points

const String _edgeEl = '[data-el="button:Continue"]';

const Probe flowwalkProbe = Probe(
  name: 'flowwalk',
  summary: 'a tap inside a tile advances the parent row, and the grid survives',
  // Everything here is a GET: the lens swaps are `htmx.ajax('GET', ...)` and
  // arming/advancing the walk are viewer-state route reads. Nothing is written
  // into the served project, so this runs against any target.
  mutates: false,
  // This probe's original prints a bare `PASS`/`FAIL` where every other one
  // prints `[PASS]`/`[FAIL]`. The harness reproduces that shape on request, so
  // the parity diff is of what was asserted rather than of brackets.
  bareVerdicts: true,
  body: _run,
);

Future<void> _run(ProbeContext ctx) async {
  final page = await ctx.newPage();
  final http4xx = <String>[];
  // Chrome's own /favicon.ico fetch is issued by the browser, not the
  // renderer, so it never reaches these events at all — it only ever shows up
  // as an unnamed console 404. Naming every 4xx we CAN see is what makes it
  // safe to discount the unnamed ones at the end (finding 18).
  await page.send('Network.enable');
  page.on('Network.responseReceived').listen((e) {
    final res = e.params['response'] as Map<String, dynamic>?;
    final status = (res?['status'] as num?)?.toInt() ?? 0;
    if (status >= 400) {
      http4xx.add('http $status ${'${res?['url']}'.replaceAll(ctx.base, '')}');
    }
  });

  // ALWAYS start from /design, never from /design/viewer directly. The viewer
  // route returns a NAMED FRAGMENT (#viewerSwap), so navigating a browser to
  // it yields a bare fragment with no htmx global — and the flow-walk island
  // reaches the parent through `window.parent.htmx`. Driving the real UI is
  // also the only way this probe tests what a user actually does.
  ctx.report.section('A. views lens offers no interactive mode');
  await ctx.goto(page, '/design');
  // The viewer arrives with the page, so wait for the thing the checks read —
  // the tiles — not for a number of milliseconds someone measured once.
  await probeWaitFor(
    page,
    "document.querySelectorAll('.dv-tile').length > 0",
    label: 'the viewer to render its tiles',
    report: ctx.report,
  );
  final viewsTools = ((await page.evaluate(
              "[...document.querySelectorAll('.dv-tile-tools a')]"
              ".map((a) => a.getAttribute('title') || '')") ??
          const [])
      as List)
      .map((t) => '$t')
      .toList();
  final distinctTitles = viewsTools.toSet().join(' | ');
  _check(
    ctx,
    'no walk control in views',
    !viewsTools
        .any((t) => RegExp('walk the flow', caseSensitive: false).hasMatch(t)),
    'titles: ${distinctTitles.isEmpty ? '(none)' : distinctTitles}',
  );
  _check(ctx, 'no advance control in views',
      !viewsTools.any((t) => RegExp('^advance', caseSensitive: false).hasMatch(t)));

  // The state must be clamped too, not just the control: a stale ?live= in the
  // URL used to paint an interactive, uncloseable tile in views. Driven through
  // the parent's own htmx so the page (and its htmx global) stay intact.
  await _lens(page,
      '/design/viewer?mode=views&flow=$_flow&step=$_from&live=$_from');
  // Nothing to poll FOR here — the assertion is an absence, and "wait until
  // zero tiles are live" is satisfied instantly by a page that has not rendered
  // yet, which would make the check vacuous. Wait for the tiles to exist (the
  // precondition), then assert none of them is live.
  await probeWaitFor(
    page,
    "document.querySelectorAll('.dv-tile').length > 0",
    label: 'the views lens to re-render',
    report: ctx.report,
  );
  _check(ctx, 'stale walk params cannot arm a views tile',
      await _count(page, '.dv-tile.is-live') == 0);

  ctx.report.section('B. arm the walk on the flows lens');
  // Switch lens the way the mini panel does, then arm the walk from the tile's
  // own hover toolbar — the user's path, not a hand-built URL.
  await _lens(page, '/design/viewer?mode=flows');
  await probeWaitFor(
    page,
    "document.querySelector('.dv-flow-row') !== null",
    label: 'the flows lens to render its rows',
    report: ctx.report,
  );
  const walkBtn = '.dv-tile[data-id="$_from"] a[title*="Walk the flow"]';
  final hasWalk = await page.evaluate(
          'document.querySelector(${jsonEncode(walkBtn)}) !== null') ==
      true;
  _check(ctx, 'flows lens offers the walk control', hasWalk);
  // Real hover on the tile opens the CSS gate (dv-tile-chrome), then a plain
  // click exercises the actual reveal — not a synthetic dispatch, which would
  // bypass the gate and keep passing even if the reveal broke (#49).
  if (hasWalk) {
    await page.hoverSelector('.dv-tile[data-id="$_from"]');
    await page.clickSelector(walkBtn);
    // Arming the walk is a server round-trip + a stage re-render. Poll for the
    // exact post-condition the next two checks assert on.
    await probeWaitFor(
      page,
      _liveIs(_from),
      label: '$_from to become the live step',
      report: ctx.report,
    );
  }
  final activeBefore = await _liveIds(page);
  _check(ctx, 'exactly one tile is the current step', activeBefore.length == 1,
      activeBefore.join(','));
  _check(ctx, 'the step is $_from',
      activeBefore.isNotEmpty && activeBefore.first == _from,
      '${activeBefore.isNotEmpty ? activeBefore.first : null}');

  // Mark every iframe so grid destruction is detectable.
  await page.evaluate(
      "[...document.querySelectorAll('iframe')].forEach((f,i)=>f.__walk='w'+i)");
  final framesBefore =
      await page.evaluate("document.querySelectorAll('iframe').length");

  ctx.report.section('C. tap Continue INSIDE the tile iframe');
  final tileFrame =
      await page.frameForSelector('.dv-tile[data-id="$_from"] iframe');
  if (tileFrame == null) {
    throw StateError('no iframe in the $_from tile — the walk was never armed,'
        ' so nothing below could distinguish a broken walk from a missing one');
  }
  _check(
      ctx,
      'flow-walk island loaded in the walked tile',
      await page.evaluateInFrame(tileFrame,
              "!!document.querySelector('script[src*=\"flowwalk.js\"]')") ==
          true);
  // The island reaches the row through window.parent.htmx. If the parent is a
  // bare fragment (or cross-origin) it bails silently, so assert the bridge
  // exists rather than inferring it from a passing end state. Evaluated in the
  // FRAME's own world: read from the parent, `window.parent` would resolve to
  // the parent itself and the check would pass unconditionally.
  _check(
      ctx,
      'parent htmx bridge reachable from inside the tile',
      await page.evaluateInFrame(tileFrame,
              "(()=>{try{return typeof window.parent.htmx==='object'}catch(e){return false}})()") ==
          true);

  final hasTarget = await page.evaluateInFrame(
          tileFrame, 'document.querySelector(${jsonEncode(_edgeEl)}) !== null') ==
      true;
  _check(ctx, 'the edge element exists on the screen', hasTarget);

  if (hasTarget) {
    await page.clickSelectorInFrame(tileFrame, _edgeEl);
    // The advance crosses an iframe boundary (island → window.parent.htmx →
    // row swap), so it is the slowest step in the probe and was the one most
    // likely to be read mid-flight. Poll for the row having actually advanced.
    await probeWaitFor(
      page,
      _liveIs(_to),
      label: 'the row to advance to $_to',
      report: ctx.report,
    );
  }

  ctx.report.section('D. the ROW advanced, the grid survived');
  final activeAfter = await _liveIds(page);
  _check(
      ctx,
      'active tile moved to $_to',
      activeAfter.length == 1 && activeAfter.first == _to,
      'now: ${activeAfter.isEmpty ? '(none)' : activeAfter.join(',')}');

  final kept = await page.evaluate(
      "[...document.querySelectorAll('iframe')].filter(f=>f.__walk!==undefined).length");
  final framesAfter =
      await page.evaluate("document.querySelectorAll('iframe').length");
  _check(ctx, 'iframes survived the advance (morph, not rebuild)',
      kept == framesBefore, '$kept/$framesBefore kept, $framesAfter present');

  // The whole point of the walk: the tile keeps showing the screen it is
  // labelled with. If the in-frame navigation were not suppressed, the row
  // would show the destination screen twice.
  // Read the frame's LIVE url, not its src attribute: hx-boost swaps the
  // document in place, so a navigated frame keeps its original src and the
  // attribute check would pass on exactly the failure it is meant to catch.
  final stillThere = await page.frameForSelector(
      '.dv-tile[data-id="$_from"] iframe',
      timeout: const Duration(seconds: 2));
  String? liveUrl;
  if (stillThere != null) {
    try {
      liveUrl = '${await page.evaluateInFrame(stillThere, 'location.pathname')}';
    } on CdpException {
      liveUrl = null;
    }
  }
  _check(ctx, '$_from tile still shows its own screen (in-frame nav suppressed)',
      liveUrl != null && liveUrl.contains(_from), liveUrl ?? '(tile gone)');
  _check(ctx, 'the source tile is no longer the active step',
      !activeAfter.contains(_from));

  ctx.report.section('errors');
  final named4xx =
      http4xx.where((e) => !RegExp('favicon', caseSensitive: false).hasMatch(e))
          .toList();
  // Drop the unnamed console 404s that have no matching named 4xx: that is
  // Chrome's own favicon fetch (finding 18), cosmetic and not ours.
  final errs = <String>[
    ...page.pageErrors.map((e) => 'page: $e'),
    ...page.consoleErrors.map(
        (e) => 'console: ${e.length > 120 ? e.substring(0, 120) : e}'),
  ];
  final real = errs.where((e) {
    if (RegExp('page:').hasMatch(e)) return true;
    if (RegExp('Failed to load resource').hasMatch(e) && named4xx.isEmpty) {
      return false;
    }
    return true;
  }).toList();
  for (final e in named4xx) {
    ctx.report.out.writeln('  ! $e');
  }
  ctx.report.out.writeln(real.isNotEmpty
      ? real.take(6).map((e) => '  ! $e').join('\n')
      : '  none');
  _check(ctx, 'no page errors or unexplained 4xx',
      real.isEmpty && named4xx.isEmpty);

  await ctx.closePage(page);
}

/// Record a check.
///
/// Kept as one indirection even though it now forwards unchanged: the verdict
/// shape for this probe is a single decision, and it was worth one function to
/// make switching it a one-line change rather than a 14-site sweep.
void _check(ProbeContext ctx, String label, bool ok, [String detail = '']) =>
    ctx.report.check(label, ok, detail);

/// Swap the viewer lens through the page's own htmx, the way the mini panel
/// does. A `goto` would work for the markup and destroy the htmx global the
/// in-frame island reaches back through.
Future<void> _lens(CdpSession page, String url) => page.evaluate(
    "window.htmx.ajax('GET', ${jsonEncode(url)},"
    " { target: '#design-viewer', swap: 'morph:outerHTML' })");

/// The condition "exactly one tile is live, and it is [id]".
String _liveIs(String id) =>
    "(() => { const live = document.querySelectorAll('.dv-tile.is-live');"
    ' return live.length === 1 && live[0].dataset.id === ${jsonEncode(id)}; })()';

Future<List<String>> _liveIds(CdpSession page) async {
  final ids = await page.evaluate(
      "[...document.querySelectorAll('.dv-tile.is-live')].map((t) => t.dataset.id)");
  return ((ids ?? const []) as List).map((e) => '$e').toList();
}

Future<int> _count(CdpSession page, String selector) async {
  final n = await page
      .evaluate('document.querySelectorAll(${jsonEncode(selector)}).length');
  return n is num ? n.toInt() : 0;
}
