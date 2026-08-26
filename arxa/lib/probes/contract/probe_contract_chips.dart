// contract-chips — the chip box model and the icon-centering gate, on every
// surface the design serves.
//
// Two rules, both read from computed style rather than from the stylesheet, so
// they hold regardless of how the design arrived at them:
//
//   1. THE CHIP BOX MODEL. `.chip` is one base widget: inline-flex, items
//      centered, pill radius (assets/css/widgets.css, D2). A chip that loses
//      the base rule still renders — as a bare inline span with square corners
//      — and it looks like a styling nit rather than the widget contract
//      breaking. "Pill" is measured as radius >= half the element's height
//      rather than compared to a literal 999px: the rounded end is the
//      contract, and a design that reaches it with 50% is not in violation.
//
//   2. THE ICON-CENTERING GATE. Every `button svg`, `summary svg` and
//      `.chip .status-dot` sits within 1px of its parent's vertical centre.
//      This encodes commit a02ceaa as a UNIVERSAL check: a `margin-top: .3rem`
//      on `.status-dot` pushed every status pill's dot off-centre, and nothing
//      caught it, because an off-centre glyph renders perfectly and simply
//      looks slightly wrong. Placing it here rather than in the studio's
//      panel-contract probe is deliberate — the defect is a property of how
//      arxa composes controls, not of the studio.
//
// A surface with zero chips is NOT a failure, and a design with no chips
// anywhere passes: the counts are printed per surface so a vacuous-looking
// pass explains itself.

import 'package:arxa/probes/contract/surface_walk.dart';
import 'package:arxa/probes/probe_base.dart';

/// `arxa design probe contract-chips`.
const Probe contractChipsProbe = Probe(
  name: 'contract-chips',
  summary:
      'every declared surface: chips keep the pill box model, glyphs centre in their control',
  suite: kSuiteContract,
  // Read-only in behaviour — GETs only, no clicks, no POSTs — but marked as
  // mutating for the same measured reason as contract-panels: this design
  // declares state-changing GET routes, so walking every declared surface
  // leaves the served project changed. See that probe's note.
  mutates: true,
  body: _run,
);

/// Read chip geometry and glyph centring from one surface.
///
/// Both reads filter out zero-rect elements: a chip inside a collapsed
/// `<details>` or a hidden panel has no box to measure, and asserting that its
/// nonexistent centre matches its parent's is noise that fails at random.
/// Centres are compared as fractions — rounding before a 1px test throws away
/// exactly the resolution the test is about.
///
/// A RAW string: this is JavaScript, and `$` and `\` are its punctuation, not
/// Dart's. `/^(inline-)?(flex|grid)$/` reads as a Dart interpolation otherwise.
const String _read = r'''
(() => {
  const vis = (el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; };

  const chips = [];
  for (const el of document.querySelectorAll('.chip')) {
    if (!vis(el)) continue;
    const cs = getComputedStyle(el);
    const h = el.getBoundingClientRect().height;
    // Computed border-radius is a length or a percentage; both mean "pill"
    // when they round the ends. Take the smallest corner: one square corner
    // is a broken pill.
    const corners = [cs.borderTopLeftRadius, cs.borderTopRightRadius,
                     cs.borderBottomLeftRadius, cs.borderBottomRightRadius];
    let minR = Infinity;
    for (const c of corners) {
      const first = String(c).split(' ')[0];
      const v = first.endsWith('%') ? (parseFloat(first) / 100) * h : parseFloat(first);
      if (!isNaN(v) && v < minR) minR = v;
    }
    chips.push({ cls: el.className, display: cs.display, align: cs.alignItems,
                 radius: minR, height: h });
  }

  const glyphs = [];
  for (const el of document.querySelectorAll('button svg, summary svg, .chip .status-dot')) {
    // Measured against the CONTROL, not against `parentElement`. A glyph is
    // routinely wrapped in an inline <span> for styling, and an inline box is
    // sized by font metrics rather than by its contents — so the wrapper's
    // centre sits a pixel or two off the glyph's however perfectly the icon is
    // centred in the button the user actually sees. Comparing to the wrapper
    // measures the line box; comparing to the control measures the contract,
    // which is what a02ceaa broke (a dot pushed off-centre WITHIN its chip).
    const ctl = el.closest('button, summary, .chip');
    if (!ctl || !vis(el) || !vis(ctl)) continue;
    const ccs = getComputedStyle(ctl);
    // Only a control that DECLARES centring is held to it. A card-shaped
    // button stacks an icon above a heading and never promised to centre it
    // vertically (button.level-card here is 24px off, correctly). Asserting
    // against a promise the control never made is how a universal gate earns
    // a reputation for false positives and gets switched off.
    const centres = /^(inline-)?(flex|grid)$/.test(ccs.display) && ccs.alignItems === 'center';
    const r = el.getBoundingClientRect(), cr = ctl.getBoundingClientRect();
    glyphs.push({ tag: el.tagName.toLowerCase(), cls: String(el.getAttribute('class') || ''),
                  parent: ctl.tagName.toLowerCase() + (ctl.className ? '.' + String(ctl.className).split(/\s+/)[0] : ''),
                  centres,
                  delta: Math.abs((r.top + r.height / 2) - (cr.top + cr.height / 2)) });
  }
  return { chips, glyphs };
})()''';

Future<void> _run(ProbeContext ctx) async {
  final rep = ctx.report;
  final badBox = <String>[];
  final offCentre = <String>[];
  var chipTotal = 0;
  var glyphTotal = 0;
  var centredTotal = 0;
  var uncentred = 0;
  var worstDelta = 0.0;

  rep.section('chip box model and glyph centring across every declared surface');
  final walk = await walkSurfaces(
    ctx,
    read: _read,
    onSurface: (path, data) {
      final d = data as Map<String, dynamic>;
      final chips = (d['chips'] as List);
      final glyphs = (d['glyphs'] as List);
      chipTotal += chips.length;
      glyphTotal += glyphs.length;

      for (final c in chips.cast<Map<String, dynamic>>()) {
        final display = '${c['display']}';
        final align = '${c['align']}';
        final radius = (c['radius'] as num?)?.toDouble() ?? 0;
        final height = (c['height'] as num?)?.toDouble() ?? 0;
        final why = <String>[];
        // `flex` counts as well as `inline-flex`, and this is not slack. CSS
        // blockifies a flex/grid ITEM: a chip that is a direct child of a flex
        // container computes to `display: flex` however it was authored, so an
        // equality test against `inline-flex` reds 161 correct chips in this
        // design alone. What the contract actually requires is that the chip
        // BE a flex container — an unstyled chip computes `inline` or `block`
        // and still fails.
        if (display != 'inline-flex' && display != 'flex') {
          why.add('display=$display');
        }
        if (align != 'center') why.add('align-items=$align');
        // Half the height is the pill threshold, with the half-pixel of slack
        // a fractional layout needs.
        if (radius + 0.5 < height / 2) {
          why.add('radius=${radius.toStringAsFixed(1)} for height'
              ' ${height.toStringAsFixed(1)}');
        }
        if (why.isNotEmpty) {
          badBox.add('$path: .${'${c['cls']}'.split(' ').join('.')}'
              ' — ${why.join(', ')}');
        }
      }

      for (final g in glyphs.cast<Map<String, dynamic>>()) {
        if (g['centres'] != true) {
          uncentred++;
          continue;
        }
        centredTotal++;
        final delta = (g['delta'] as num).toDouble();
        if (delta > worstDelta) worstDelta = delta;
        if (delta > 1.0) {
          offCentre.add('$path: ${g['tag']}'
              '${'${g['cls']}'.isEmpty ? '' : '.${g['cls']}'}'
              ' in ${g['parent']} off by ${delta.toStringAsFixed(2)}px');
        }
      }

      final held = glyphs.where((g) => (g as Map)['centres'] == true).length;
      rep.out.writeln('  $path — chips: ${chips.length}'
          ' · glyphs: ${glyphs.length} ($held in centring controls)');
    },
  );

  reportWalk(rep, walk);
  rep.out.writeln('  totals: $chipTotal chip(s) and $glyphTotal glyph(s)'
      ' across ${walk.loaded.length} surface(s); $centredTotal glyph(s) held to'
      ' the centring rule, $uncentred in controls that do not declare centring;'
      ' worst offset ${worstDelta.toStringAsFixed(2)}px');

  if (chipTotal == 0) {
    rep.skip('this design renders no chips on any loadable surface — the box'
        ' model rule is true of an empty set, and passes vacuously');
  }
  if (centredTotal == 0) {
    rep.skip('no glyph on any surface sits in a control that declares centring'
        ' — the centring rule passes vacuously');
  }

  rep.check('every chip keeps the pill box model', badBox.isEmpty,
      badBox.isEmpty
          ? '$chipTotal chip(s) inline-flex, centred, pill-radiused'
          : '${badBox.length} bad: ${badBox.take(6).join('; ')}');
  rep.check('every glyph centres within 1px of its control', offCentre.isEmpty,
      offCentre.isEmpty
          ? '$centredTotal glyph(s), worst ${worstDelta.toStringAsFixed(2)}px'
          : '${offCentre.length} off: ${offCentre.take(6).join('; ')}');
}
