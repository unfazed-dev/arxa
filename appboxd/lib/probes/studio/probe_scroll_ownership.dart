// probe_scroll_ownership.dart — the shell is viewport-locked; panels own scroll.
//
// The doctrine this enforces is the studio's own, stated in
// designs/appbox-studio/assets/css/app.css ("THE SHELL IS VIEWPORT-LOCKED";
// v2 carries the doctrine under ui/styles/common/ — cited at its v1 home:
// at the expanded rung the PAGE never scrolls, no shell REGION is a scroll
// container, and scrolling belongs to the panels — each panel owns its own
// scroller. It is a studio probe, not a contract probe, because the doctrine
// is written in this design's stylesheet, not (yet) in the appbox opinion —
// hello-hda is free to let its page scroll.
//
// The regression that motivated it had TWO shapes, and the probe asserts
// against both:
//   1. the shell region as scroller — `.shell-main { overflow-y: auto }`
//      parked the scroll on layout chrome (caught by the computed-style check);
//   2. the missing height chain — without the region being a flex column the
//      panel grew past the lock and `#app { overflow: hidden }` CLIPPED it,
//      leaving content unreachable while the page still "didn't scroll".
//      `#app.scrollHeight` reports full content height regardless of
//      overflow: hidden, so overgrowth that is not contained inside a
//      descendant scroll container is measurable (a working inner scroller is
//      its own scroll container, so its content does NOT propagate up).
//
// Route discovery reuses the contract walk (`/__routes`) rather than naming
// routes, so a new studio surface is covered the day it is declared. Known
// cost inherited from the walk: the two tray routes time out (~30s each,
// tracked in task #22) and land in `unreadable`, loudly.
import 'package:appboxd/probes/contract/surface_walk.dart';
import 'package:appboxd/probes/probe_base.dart';

/// Mutating for the same reason the contract probes are: the studio declares
/// state-changing GETs, so even a read-only walk writes to the served project.
const Probe scrollOwnershipProbe = Probe(
  name: 'scroll-ownership',
  summary: 'the shell is viewport-locked — panels own every scroller',
  mutates: true,
  body: _run,
);

/// Read in the main frame of each document surface, at the walk's default
/// viewport (1600×1000 — the expanded rung, the only rung the lock applies
/// to; below 840px the page IS the scroller by the same doctrine).
const String _readJs = r'''
(() => {
  const app = document.getElementById('app');
  if (!app) return { hasApp: false };
  const doc = document.documentElement;
  const scrollers = [...document.querySelectorAll('.shell-main')]
    .filter((el) => {
      const oy = getComputedStyle(el).overflowY;
      return oy === 'auto' || oy === 'scroll';
    })
    .map((el) => el.className);
  return {
    hasApp: true,
    appLocked: getComputedStyle(app).overflow === 'hidden',
    pageOverflow: doc.scrollHeight - doc.clientHeight,
    clipOverflow: app.scrollHeight - app.clientHeight,
    regionScrollers: scrollers,
  };
})()
''';

Future<void> _run(ProbeContext ctx) async {
  final rep = ctx.report;
  var appSurfaces = 0;
  final noApp = <String>[];

  final walk = await walkSurfaces(ctx, read: _readJs,
      onSurface: (path, data) {
    if (data is! Map || data['hasApp'] != true) {
      // A document without the #app shell (if the design ever serves one) is
      // outside the doctrine — counted and printed, never silently passed.
      noApp.add(path);
      return;
    }
    appSurfaces++;
    rep.check('$path: #app declares the lock (overflow: hidden)',
        data['appLocked'] == true);
    // ±2px: fractional layout sizes round differently across scroll/client.
    rep.check('$path: the page does not scroll',
        (data['pageOverflow'] as num) <= 2, '${data['pageOverflow']}px over');
    rep.check(
        '$path: nothing is clipped inside the lock (overgrowth must live in a'
        ' panel scroller)',
        (data['clipOverflow'] as num) <= 2,
        '${data['clipOverflow']}px over');
    final scrollers = data['regionScrollers'] as List? ?? const [];
    rep.check('$path: no shell region is a scroll container',
        scrollers.isEmpty, scrollers.join(', '));
  });

  if (noApp.isNotEmpty) {
    rep.skip('${noApp.length} document surface(s) without #app — outside the'
        ' viewport-lock doctrine: ${noApp.join(', ')}');
  }
  reportWalk(rep, walk);
  rep.check('at least one #app surface asserted', appSurfaces > 0,
      '$appSurfaces of ${walk.loaded.length} loaded');
}
