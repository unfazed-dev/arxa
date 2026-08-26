// The contract suite's surface walk — how a probe finds what to assert about
// WITHOUT knowing which design it is pointed at.
//
// Every contract probe asks the served design what it serves (`GET /__routes`)
// and walks the answer. No probe in this directory may name a route; that is
// greppable at acceptance and is the whole basis of design-agnosticism. See
// docs/plans/design-derived-contract-probes.md.
//
// Two exclusions, both counted and printed rather than applied silently — a
// probe whose denominator shrinks invisibly is a probe that passes vacuously:
//
//   - PARAMETERIZED routes (`/x/:id`). A value for `:id` can only come from
//     knowing the design. Inventing one yields a 404, and asserting about an
//     error page is worse than asserting about nothing. Deferred to v2, where
//     the scaffolder's per-app manifest can supply real values.
//   - FRAGMENT responses. Most designs serve htmx partials alongside their
//     documents; this design serves 29 of them against 25 documents. A
//     fragment loaded as a top-level document has no `<head>`, so it has no
//     stylesheet: `getComputedStyle` reports UA defaults and every chip reads
//     `display: inline`. A check that fails there is not catching a design
//     defect, it is measuring a page that never exists in the product. The
//     panel shape has the same problem in reverse — an out-of-band section
//     arrives without the role panel it will be swapped into.
//
// Fragments are detected by `document.doctype`, which Chrome leaves null for
// markup that never declared one. Cheap, and it asks the browser the same
// question the browser already answered when it chose quirks mode.

import 'package:arxa/probes/probe_base.dart';

/// What a walk actually covered. Printed by every contract probe so a
/// green run states its own denominator.
class SurfaceWalk {
  /// Document surfaces loaded and asserted about.
  final List<String> loaded = [];

  /// Routes skipped for carrying a `:param` segment.
  final List<String> parameterized = [];

  /// Routes that answered with a fragment rather than a document.
  final List<String> fragments = [];

  /// Routes that could not be read at all, with the reason.
  final List<String> unreadable = [];

  /// One line summarising the walk, for the probe's own output.
  String get summary =>
      '${loaded.length} document surface(s) asserted; skipped '
      '${parameterized.length} parameterized, ${fragments.length} fragment, '
      '${unreadable.length} unreadable';
}

/// Walk every loadable surface the design declares, evaluating [read] on each.
///
/// [read] is a JavaScript expression returning whatever the probe wants to
/// assert about; [onSurface] receives it once per document surface, with the
/// path it came from. The expression is evaluated in the MAIN frame only:
/// `querySelectorAll` does not descend into iframes, which is load-bearing
/// here — a design that renders screens in tiles (this one shows a canvas of
/// them) would otherwise report one header panel per tile and fail an
/// at-most-once rule that is actually satisfied.
///
/// Throws when the route table cannot be read: a contract probe with no
/// surfaces has nothing to say, and saying it quietly would exit 0.
Future<SurfaceWalk> walkSurfaces(
  ProbeContext ctx, {
  required String read,
  required void Function(String path, dynamic data) onSurface,
}) async {
  final res = await fetchRoutes(ctx.base);
  if (res.routes == null) {
    throw StateError('could not read the design\'s route table from'
        ' ${ctx.base}/__routes (${res.error}) — a contract probe derives its'
        ' targets from the design and cannot run without it');
  }
  final walk = SurfaceWalk();
  for (final r in res.routes!) {
    if (r.method.toUpperCase() == 'GET' && r.isParameterized) {
      walk.parameterized.add(r.path);
    }
  }

  final page = await ctx.newPage();
  // One page for the whole walk, not one per route: nothing here carries state
  // between surfaces, and a fresh target per route would open dozens of them
  // on a machine where Chrome's per-profile disk cost is a known failure mode.
  try {
    for (final route in res.loadableGets) {
      try {
        await ctx.goto(page, route.path);
      } catch (e) {
        walk.unreadable.add('${route.path} ($e)');
        continue;
      }
      final probed = await page.evaluate(
          '(() => { const isDoc = document.doctype !== null;'
          ' return { isDoc, data: isDoc ? ($read) : null }; })()');
      if (probed is! Map || probed['isDoc'] != true) {
        walk.fragments.add(route.path);
        continue;
      }
      walk.loaded.add(route.path);
      onSurface(route.path, probed['data']);
    }
  } finally {
    await ctx.closePage(page);
  }
  return walk;
}

/// Print the walk's denominator, then fail if it asserted about nothing.
///
/// A design that declares no loadable document surface is not a design this
/// probe passed against — it is a probe that ran out of things to check. That
/// is a failure, reported as one, in the same spirit as the CLI refusing an
/// empty suite.
void reportWalk(ProbeReport rep, SurfaceWalk walk) {
  rep.out.writeln('  walked: ${walk.summary}');
  if (walk.parameterized.isNotEmpty) {
    rep.skip('${walk.parameterized.length} parameterized route(s), deferred to'
        ' v2: ${walk.parameterized.take(6).join(', ')}'
        '${walk.parameterized.length > 6 ? ', …' : ''}');
  }
  if (walk.fragments.isNotEmpty) {
    rep.skip('${walk.fragments.length} fragment response(s) — no document, so'
        ' no stylesheet to compute against');
  }
  for (final u in walk.unreadable) {
    rep.warn('could not load $u');
  }
  rep.check('the design declared at least one loadable document surface',
      walk.loaded.isNotEmpty, '${walk.loaded.length} loaded');
}
