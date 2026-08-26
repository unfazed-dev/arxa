// probe_panel_resize.dart — panels resize from their inner EDGE, and releasing
// the drag must not disturb anything else on the page.
// Ported from `archives/tooling-pre-dart/tools/studio-probes/probe-panel-resize.mjs`.
//
// WHY THIS EXISTS: two bugs, both invisible to a server-render probe.
//
// 1. DIRECTION. drag.js computed `startW + (clientX - sx)`, which silently
//    assumes you grabbed an END edge. The composer's rail sits on its end
//    edge, the activity panel's on its start edge — a single fixed sign is
//    wrong for whichever panel doesn't match it, and the panel fought the
//    pointer: drag right, panel grows, edge runs away from the cursor. The
//    sign has to come from which edge you grabbed (`data-edge`, start|end),
//    never from `data-persist`, which is an opaque server key, not a position.
//
// 2. THE FLASH. On release drag.js POSTed the new width and swapped the whole
//    panel back in. htmx runs with globalViewTransitions:true, and
//    `.panel-activity` has no `view-transition-name` of its own — so it was
//    captured in the ROOT snapshot and the browser cross-faded the ENTIRE
//    page. Letting go of the drag looked like the app reloading itself. The
//    client already holds the final width; the server only needs to record it,
//    so the request must not swap.
//
// Needs a browser: both bugs live in pointer handling and the swap's
// animation, neither of which exists in the HTML.
//
// PORT NOTE — the drags here are multi-step on purpose. `CdpSession.drag`
// defaults to `steps: 14`, which is the value these interactions were tuned
// against: a two-point drag is invisible to drag-threshold detection, and a
// resize probe built on one reports a working divider broken.
import 'dart:async';
import 'dart:convert';

import 'package:arxa/cdp.dart';
import 'package:arxa/probes/probe_base.dart';

/// Sections C and D leave a recorded width behind (`POST /design/panel/size/`),
/// so this writes into whatever project the server is bound to.
const Probe panelResizeProbe = Probe(
  name: 'panel-resize',
  summary: 'panels resize from their inner edge and releasing does not reload',
  mutates: true,
  body: _run,
);

/// Count view transitions, and record every request with the wall clock, so
/// "did the release disturb the page?" is measured rather than eyeballed.
///
/// The node tagging is the load-bearing half: htmx still EMITS beforeSwap for a
/// `swap:'none'` request, so counting that event proves nothing — what matters
/// is whether any node was actually replaced. Morph keeps nodes; a re-render
/// does not.
const String _instrumentJs = r'''
(() => {
  window.__vt = 0;
  const orig = document.startViewTransition && document.startViewTransition.bind(document);
  if (orig) document.startViewTransition = (cb) => { window.__vt++; return orig(cb); };
  document.querySelectorAll('.panel-activity *, .panel-composer *')
    .forEach((n) => { n.__orig = 1; });
})()
''';

/// Read the width badge, the rendered box and the CSS limits together.
///
/// Called from inside [CdpSession.drag]'s `beforeRelease`, so it runs after the
/// final interpolated move with the button still down — `pointerup` removes the
/// badge, and a post-release read finds null and makes every assertion in
/// section E pass vacuously.
String _sampleJs(String panel) => '(() => {'
    ' const el = document.querySelector(${jsonEncode(panel)});'
    ' if (!el) return null;'
    ' const b = el.querySelector(".panel-resize-width");'
    ' const cs = getComputedStyle(el);'
    ' return { badge: b ? parseFloat(b.textContent) : null,'
    '          box: Math.round(el.getBoundingClientRect().width),'
    '          min: parseFloat(cs.minWidth),'
    '          max: parseFloat(cs.maxWidth) }; })()';

const String _nodesKeptJs = r'''
(() => {
  const live = [...document.querySelectorAll('.panel-activity *, .panel-composer *')];
  return { kept: live.filter((n) => n.__orig).length, total: live.length };
})()
''';

Future<void> _run(ProbeContext ctx) async {
  final report = ctx.report;
  final page = await ctx.newPage(width: 1900, height: 1000);
  try {
    report.section('A. the rail is the edge, not an icon');
    await ctx.goto(page, '/design');
    final rails = await page.evaluate(r'''
(() => [...document.querySelectorAll('.panel-resize')].map((e) => ({
  host: e.closest('.panel-composer') ? 'composer' : 'activity',
  cursor: getComputedStyle(e).cursor,
  edge: e.dataset.edge,
  kids: e.children.length,
  aria: !!e.getAttribute('aria-label'),
  atInnerEdge: e.closest('.panel-composer')
    ? Math.abs(e.getBoundingClientRect().right - e.closest('.panel-composer').getBoundingClientRect().right) < 2
    : Math.abs(e.getBoundingClientRect().left - e.closest('.panel-activity').getBoundingClientRect().left) < 2,
})))()''');
    final rs = rails is List
        ? rails.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
        : <Map<String, dynamic>>[];
    report.check('both panels expose a rail', rs.length == 2,
        jsonEncode(rs.map((r) => r['host']).toList()));
    report.check('rails carry no icon', rs.every((r) => r['kids'] == 0),
        jsonEncode(rs.map((r) => r['kids']).toList()));
    report.check('rails keep an aria-label', rs.every((r) => r['aria'] == true));
    report.check('rails show a col-resize cursor',
        rs.every((r) => r['cursor'] == 'col-resize'));
    report.check(
        'each rail sits on its panel INNER edge',
        rs.every((r) => r['atInnerEdge'] == true),
        jsonEncode(
            rs.map((r) => '${r['host']}:${r['edge']}=${r['atInnerEdge']}').toList()));
    report.check(
        'composer rail is its end edge, activity rail its start',
        _railFor(rs, 'composer')?['edge'] == 'end' &&
            _railFor(rs, 'activity')?['edge'] == 'start',
        jsonEncode(rs.map((r) => '${r['host']}=${r['edge']}').toList()));

    report.section('B. the edge follows the pointer (sign per edge)');
    // This section measures the SIGN and the distance, so every drag must stay
    // strictly inside both panels' limits — a clamp here would look identical
    // to an inverted or ignored drag. The tightest range is the composer's
    // [390, 500]; 445 ± 45 sits 10px clear of both ends of it. Section E is
    // where the limits themselves get tested, by overshooting them on purpose.
    for (final t in const [
      ('composer end-edge', '.panel-composer', 45, 'wider'),
      ('composer end-edge', '.panel-composer', -45, 'narrower'),
      ('activity start-edge', '.panel-activity', 45, 'narrower'),
      ('activity start-edge', '.panel-activity', -45, 'wider'),
    ]) {
      final r = await _dragRail(ctx, page, t.$2, t.$3, from: 445);
      if (r == null) {
        report.check('${t.$1}: drag ${_sign(t.$3)} makes it ${t.$4}', false,
            'no rail on ${t.$2}');
        report.check('${t.$1}: honours the dragged distance', false, 'no rail');
        continue;
      }
      final got = r.after > r.before + 5
          ? 'wider'
          : r.after < r.before - 5
              ? 'narrower'
              : 'unchanged';
      report.check('${t.$1}: drag ${_sign(t.$3)} makes it ${t.$4}', got == t.$4,
          '${r.before} -> ${r.after}');
      report.check(
          '${t.$1}: honours the dragged distance',
          ((r.after - r.before).abs() - t.$3.abs()).abs() < 18,
          'moved ${(r.after - r.before).abs()}px');
    }

    report.section('C. releasing must not refresh the page');
    {
      final r = await _dragRail(ctx, page, '.panel-activity', -40);
      if (r == null) {
        report.check('release starts NO view transition', false, 'no rail');
      } else {
        // THE REGRESSION: a swap here cross-fades the whole document, because
        // .panel-activity has no view-transition-name and lands in the root
        // snapshot.
        report.check('release starts NO view transition', r.vt == 0,
            '${r.vt} started');
        report.check('release replaces no panel node', r.kept == r.total,
            '${r.kept}/${r.total} original nodes still live');
        report.check(
            'release still records the width server-side',
            r.releaseReqs.any((q) => q.startsWith('POST /design/panel/size/')),
            jsonEncode(r.releaseReqs));
      }
    }
    {
      final r = await _dragRail(ctx, page, '.panel-composer', 70);
      if (r == null) {
        report.check('composer release makes no request at all (no server width)',
            false, 'no rail');
      } else {
        report.check(
            'composer release makes no request at all (no server width)',
            r.releaseReqs.isEmpty,
            jsonEncode(r.releaseReqs));
        report.check('composer release starts no view transition', r.vt == 0,
            '${r.vt} started');
      }
    }

    report.section('D. the width survives a reload');
    {
      // -40 from 450 lands on 490, clear of the 500 cap: a drag that clamped
      // would still "persist across a reload" while proving nothing about the
      // drag, since both sides of the comparison would be the ceiling.
      await _dragRail(ctx, page, '.panel-activity', -40);
      final dragged = await _widthOf(page, '.panel-activity');
      await ctx.goto(page, '/design');
      final reloaded = await _widthOf(page, '.panel-activity');
      report.check(
          'activity width persists across a reload',
          dragged != null && reloaded != null && (reloaded - dragged).abs() < 3,
          '$dragged -> $reloaded');
    }

    // LAST, deliberately: every drag below overshoots a limit, so it leaves the
    // activity panel pinned at 340 or 600. A section that ran after this one
    // would start from an extreme and its own drag would clamp to a no-op —
    // passing while testing nothing.
    report.section('E. the readout equals the panel (badge maths)');
    // THE BUG THIS CATCHES: drag.js clamped to a hardcoded [200, 600] — a pair
    // of numbers that matched NO panel. The composer floors at 360px and
    // ceilings at 576px; the activity panel floors at 340px. Past a limit,
    // min/max-width held the element still while the badge kept counting, so
    // the readout reported 160px of travel that never happened. The limits live
    // in CSS now and drag.js reads them, so the invariant is simply: the number
    // equals the box.
    //
    // Every drag below OVERSHOOTS its limit deliberately — a drag that stays in
    // range agrees with a hardcoded clamp too, and would have passed all along.
    for (final t in const [
      ('composer past its floor', '.panel-composer', -260, 'min'),
      ('composer past its ceiling', '.panel-composer', 300, 'max'),
      ('activity past its floor', '.panel-activity', 260, 'min'),
      ('activity past its ceiling', '.panel-activity', -300, 'max'),
    ]) {
      final s = await _badgeVsBox(ctx, page, t.$2, t.$3);
      final badge = s?['badge'];
      final box = s?['box'];
      final limit = s?[t.$4];
      final has = badge is num;
      // The vacuity guard. A missing sample is a FAILED check, never a skip:
      // this check existing is the only thing standing between a null badge
      // and twelve passes that assert nothing.
      report.check('${t.$1}: badge exists mid-drag', has,
          'null badge would make the checks below vacuous');
      report.check(
          '${t.$1}: badge equals the rendered width',
          has && box is num && (badge - box).abs() <= 1,
          'badge=$badge box=$box');
      report.check(
          '${t.$1}: stops AT the CSS ${t.$4}-width',
          has && limit is num && (badge - limit).abs() <= 1,
          'badge=$badge css ${t.$4}-width=$limit');
    }
  } finally {
    await ctx.closePage(page);
  }
}

/// Drag [panel]'s rail by [dx] and report what the width badge read at the
/// instant the button came up.
///
/// Returns null when the panel or its rail is absent; the caller's vacuity
/// guard turns that into a reported failure.
Future<Map<String, dynamic>?> _badgeVsBox(
  ProbeContext ctx,
  CdpSession page,
  String panel,
  int dx, {
  int from = 450,
}) async {
  await ctx.goto(page, '/design');
  final seeded = await page.evaluate(
    '(() => { const e = document.querySelector(${jsonEncode(panel)});'
    ' if (!e) return false; e.style.width = "${from}px"; return true; })()',
  );
  if (seeded != true) return null;
  await probeWaitFor(
    page,
    '(() => { const e = document.querySelector(${jsonEncode(panel)});'
    ' return e && Math.round(e.getBoundingClientRect().width) === $from; })()',
    timeout: const Duration(seconds: 3),
    label: 'the panel to take its seeded starting width',
    report: ctx.report,
  );
  final rail = await _railCentre(page, panel);
  if (rail == null) return null;

  Map<String, dynamic>? sample;
  await page.drag(
    rail.$1,
    rail.$2,
    rail.$1 + dx,
    rail.$2,
    beforeRelease: () async {
      final s = await page.evaluate(_sampleJs(panel));
      if (s is Map) sample = s.cast<String, dynamic>();
    },
  );
  await waitQuiet(page, timeoutMs: 2000, report: ctx.report);
  return sample;
}

/// One drag of a panel's rail, with everything the release could have
/// disturbed measured around it.
///
/// Returns null when the panel or its rail is absent, so the caller reports a
/// failed check rather than the run dying on a null dereference.
Future<_DragResult?> _dragRail(
  ProbeContext ctx,
  CdpSession page,
  String panel,
  int dx, {
  int from = 450,
}) async {
  await ctx.goto(page, '/design');
  // Start mid-range so neither min-width nor the 600px cap masks the result.
  final seeded = await page.evaluate(
    '(() => { const e = document.querySelector(${jsonEncode(panel)});'
    ' if (!e) return false; e.style.width = "${from}px"; return true; })()',
  );
  if (seeded != true) return null;
  await probeWaitFor(
    page,
    '(() => { const e = document.querySelector(${jsonEncode(panel)});'
    ' return e && Math.round(e.getBoundingClientRect().width) === $from; })()',
    timeout: const Duration(seconds: 3),
    label: 'the panel to take its seeded starting width',
    report: ctx.report,
  );
  await page.evaluate(_instrumentJs);

  final before = await _widthOf(page, panel);
  final rail = await _railCentre(page, panel);
  if (before == null || rail == null) return null;

  // Only count what the RELEASE causes. The listener goes on inside
  // `beforeRelease` — after the final interpolated move, before the button
  // comes up — which is the same bracket the original drew with
  // `p.on('request')` around `mouse.up()`. Every request, not just XHR: one of
  // the assertions is "no request at all".
  final releaseReqs = <String>[];
  await page.send('Network.enable');
  StreamSubscription<CdpEvent>? sub;
  try {
    await page.drag(
      rail.$1,
      rail.$2,
      rail.$1 + dx,
      rail.$2,
      beforeRelease: () async {
        sub = page.on('Network.requestWillBeSent').listen((e) {
          final r = e.params['request'];
          if (r is! Map) return;
          releaseReqs
              .add('${r['method']} ${'${r['url']}'.replaceFirst(ctx.base, '')}');
        });
      },
    );
    // The release POSTs and htmx settles; there is no named post-condition on
    // a request that deliberately does not swap, so this is the one place the
    // original's fixed 1100ms has no honest replacement.
    await waitQuiet(page, timeoutMs: 2000, report: ctx.report);
  } finally {
    await sub?.cancel();
  }

  final after = await _widthOf(page, panel);
  final vtRaw = await page.evaluate('window.__vt');
  final nodes = await page.evaluate(_nodesKeptJs);
  return _DragResult(
    before: before,
    after: after ?? before,
    releaseReqs: releaseReqs,
    vt: vtRaw is num ? vtRaw.toInt() : -1,
    kept: nodes is Map ? (nodes['kept'] as num?)?.toInt() ?? -1 : -1,
    total: nodes is Map ? (nodes['total'] as num?)?.toInt() ?? -2 : -2,
  );
}

Future<int?> _widthOf(CdpSession page, String selector) async {
  final w = await page.evaluate(
    '(() => { const e = document.querySelector(${jsonEncode(selector)});'
    ' return e ? Math.round(e.getBoundingClientRect().width) : null; })()',
  );
  return w is num ? w.toInt() : null;
}

Future<(int, int)?> _railCentre(CdpSession page, String panel) async {
  final r = await page.evaluate(
    '(() => { const e = document.querySelector(${jsonEncode('$panel .panel-resize')});'
    ' if (!e) return null; const b = e.getBoundingClientRect();'
    ' return { x: Math.round(b.x + b.width / 2),'
    '          y: Math.round(b.y + b.height / 2) }; })()',
  );
  if (r is! Map) return null;
  final x = r['x'], y = r['y'];
  if (x is! num || y is! num) return null;
  return (x.toInt(), y.toInt());
}

Map<String, dynamic>? _railFor(List<Map<String, dynamic>> rails, String host) {
  for (final r in rails) {
    if (r['host'] == host) return r;
  }
  return null;
}

String _sign(int dx) => dx > 0 ? '+$dx' : '$dx';

class _DragResult {
  final int before;
  final int after;
  final List<String> releaseReqs;
  final int vt;
  final int kept;
  final int total;
  const _DragResult({
    required this.before,
    required this.after,
    required this.releaseReqs,
    required this.vt,
    required this.kept,
    required this.total,
  });
}
