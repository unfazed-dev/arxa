// panel-contract — the three content panels are ONE card, not five hand-rolled
// ones, and each section lands where its grid area says it does.
//
// Dart port of `tools/probe-panel-contract.mjs` (sections A–L) onto the lens
// CDP stack. Section letters, check labels and the `[PASS]`/`[FAIL]` shape are
// preserved verbatim so the two suites diff textually while both exist.
//
// THE BUGS THIS CATCHES (carried from the .mjs header):
// - A panel that loses its card chrome still renders; it just stops matching
//   its neighbours, and nobody notices until the three are seen together.
// - A section that lands in the wrong grid area still renders — the filmstrip
//   stops being full-height of the rows, or the canvas loses width to a stray
//   child auto-placed into the side-start track. The fullscreen-close button
//   had no grid area and took 33px off the canvas.
// - A duplicated view-transition-name makes Chrome abort the WHOLE transition,
//   disabling view transitions app-wide with no error (ADR-0003).
// - A section rendered empty is a bordered strip with nothing in it.
//
// Sections A–K share ONE page on purpose: the state they accumulate IS the
// fixture. G opens a file read, which is why K has to navigate back out of it
// before measuring, and why L takes a page of its own.

import 'dart:convert';

import 'package:appboxd/cdp.dart';
import 'package:appboxd/probes/probe_base.dart';

/// `appbox design probe panel-contract`.
const Probe panelContractProbe = Probe(
  name: 'panel-contract',
  summary: 'panel card, grid areas, view-transition names, chip contract (A–L)',
  // Not a POST, but G clicks into the activity panel's FILES view and follows a
  // file link, and which surface /design shows is server-side session state —
  // the run leaves the served project changed. K's own comment is the evidence.
  // The `.mjs` original never guards; the port does, as composer-draft did.
  mutates: true,
  body: _run,
);

// The activity panel's file links, behind its FILES view rather than on the
// canvas. Used twice: as the wait condition and as the read.
const String _fileLinkSel =
    '#panel-activity-body a[hx-get*="/design/file"], a[href*="/design/file"]';

/// The chip box model, read straight off the element. Evaluated twice in L —
/// once live, once with `widgets.css` disabled — so it has to be one string.
const String _chipContract =
    "(() => [...document.querySelectorAll('.chip')].map((e) => {"
    ' const cs = getComputedStyle(e);'
    ' return { cls: e.className, display: cs.display, radius: cs.borderRadius,'
    ' borderW: cs.borderWidth, shadow: cs.boxShadow }; }))()';

Future<void> _run(ProbeContext ctx) async {
  final rep = ctx.report;
  final p = await ctx.newPage(width: 1900, height: 1000);
  await ctx.goto(p, '/design');

  await _sectionA(rep, p);
  await _sectionB(rep, p);
  await _sectionC(rep, p);
  await _sectionD(rep, p);
  await _sectionE(rep, p);
  await _sectionF(rep, p);
  await _sectionG(rep, p, ctx);
  await _sectionH(rep, p, ctx);
  await _sectionI(rep, p, ctx);
  await _sectionJ(rep, p, ctx);
  await _sectionK(rep, p, ctx);
  await _sectionL(rep, ctx);

  await ctx.closePage(p);
}

// ── A ────────────────────────────────────────────────────────────────────────

Future<void> _sectionA(ProbeReport rep, CdpSession p) async {
  rep.section('A. every panel is a card with the SAME shadow');
  final raw = await p.evaluate(
      "(() => ['.panel-composer', '.panel-viewer', '.panel-activity']"
      ' .map((s) => { const e = document.querySelector(s);'
      ' return { s, shadow: e && getComputedStyle(e).boxShadow }; }))()');
  final shadows = (raw as List).cast<Map<String, dynamic>>();
  final values = shadows.map((r) => r['shadow']).toList();

  rep.check(
      'all three content panels carry a shadow',
      shadows.every((r) => jsTruthy(r['shadow']) && r['shadow'] != 'none'),
      jsonEncode(shadows
          .map((r) => "${r['s']}=${jsTruthy(r['shadow']) ? 'set' : 'MISSING'}")
          .toList()));
  rep.check('the three shadows are IDENTICAL', values.toSet().length == 1,
      values.map((v) => v == null ? '' : '$v').join(' || '));
}

// ── B ────────────────────────────────────────────────────────────────────────

Future<void> _sectionB(ProbeReport rep, CdpSession p) async {
  rep.section('B. sections place by grid area');
  final geo = (await p.evaluate(r'''(() => {
  const v = document.querySelector('.panel-viewer');
  const box = (s) => { const e = v.querySelector(s); if (!e) return null; const r = e.getBoundingClientRect(); return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height), r: Math.round(r.right), b: Math.round(r.bottom) }; };
  const vr = v.getBoundingClientRect();
  return { panel: { x: Math.round(vr.x), y: Math.round(vr.y), w: Math.round(vr.width), r: Math.round(vr.right), b: Math.round(vr.bottom) },
    top: box('.panel-top'), body: box('.panel-body'), bottom: box('.panel-bottom'), side: box('.panel-side-end') };
})()''')) as Map<String, dynamic>;

  final panel = geo['panel'] as Map<String, dynamic>;
  final top = geo['top'] as Map<String, dynamic>?;
  final body = geo['body'] as Map<String, dynamic>?;
  final bottom = geo['bottom'] as Map<String, dynamic>?;
  final side = geo['side'] as Map<String, dynamic>?;
  final pw = panel['w'] as num;

  rep.check(
      'top spans the full panel width',
      top != null && ((top['w'] as num) - pw).abs() <= 2,
      'top=${jsUndefined(top?['w'])} panel=${jsNum(pw)}');
  rep.check(
      'bottom spans the full panel width',
      bottom != null && ((bottom['w'] as num) - pw).abs() <= 2,
      'bottom=${jsUndefined(bottom?['w'])} panel=${jsNum(pw)}');
  rep.check(
      'side-end sits to the RIGHT of the body',
      side != null && body != null && (side['x'] as num) >= (body['r'] as num) - 2,
      'body.right=${jsUndefined(body?['r'])} side.x=${jsUndefined(side?['x'])}');
  rep.check(
      'side-end starts BELOW the top section',
      side != null && top != null && (side['y'] as num) >= (top['b'] as num) - 2,
      'top.bottom=${jsUndefined(top?['b'])} side.y=${jsUndefined(side?['y'])}');
  rep.check(
      'side-end ends ABOVE the bottom section',
      side != null &&
          bottom != null &&
          (side['b'] as num) <= (bottom['y'] as num) + 2,
      'side.bottom=${jsUndefined(side?['b'])} bottom.y=${jsUndefined(bottom?['y'])}');

  // The filmstrip is a nested card inside the side-end slot: it keeps a .6rem
  // margin so its rounded corners have room to round against. It is NOT the
  // slot. So the inset is SYMMETRIC, and body + side + both margins account for
  // the panel width with nothing lost.
  final inset = (await p.evaluate(
      "(() => { const e = document.querySelector('.panel-side-end');"
      ' const cs = getComputedStyle(e);'
      ' return { l: cs.marginLeft, r: cs.marginRight }; })()')) as Map<String, dynamic>;
  rep.check('side-end inset is symmetric', inset['l'] == inset['r'],
      jsonEncode(inset));
  final m = jsParseFloat(inset['l']) ?? 0;
  rep.check(
      'body + side + its margins fill the panel width',
      body != null &&
          side != null &&
          (((body['w'] as num) + (side['w'] as num) + 2 * m) - pw).abs() <= 4,
      '${jsUndefined(body?['w'])} + ${jsUndefined(side?['w'])} + 2*${jsNum(m)} vs ${jsNum(pw)}');
  rep.check(
      'NO stray grid item stole the side-start column',
      body != null && ((body['x'] as num) - (panel['x'] as num)).abs() <= 2,
      'body.x=${jsUndefined(body?['x'])} panel.x=${jsNum(panel['x'] as num)} — a gap here'
      ' means an unplaced child auto-placed into side-start');
}

// ── C ────────────────────────────────────────────────────────────────────────

Future<void> _sectionC(ProbeReport rep, CdpSession p) async {
  rep.section('C. section on/off is real (no empty strips)');
  final empties = (await p.evaluate(
      "(() => [...document.querySelectorAll('.panel-top, .panel-bottom,"
      " .panel-side-start, .panel-side-end')]"
      ' .filter((e) => !e.textContent.trim() && !e.children.length)'
      ' .map((e) => e.className))()')) as List;
  rep.check('no section rendered empty', empties.isEmpty, jsonEncode(empties));

  final composer = (await p.evaluate(
      "(() => { const c = document.querySelector('.panel-composer');"
      " return { top: !!c.querySelector('.panel-top'),"
      " body: !!c.querySelector('.panel-body'),"
      " bottom: !!c.querySelector('.panel-bottom') }; })()")) as Map<String, dynamic>;
  rep.check('composer: top ON', composer['top'] == true);
  rep.check('composer: body ON', composer['body'] == true);
  rep.check('composer: bottom OFF', composer['bottom'] == false,
      jsonEncode(composer));

  final hf = (await p.evaluate(
      "(() => ['.panel-header', '.panel-footer'].map((s) => {"
      ' const e = document.querySelector(s); if (!e) return { s, missing: true };'
      " return { s, top: !!e.querySelector('.panel-top'),"
      " body: !!e.querySelector('.panel-body'),"
      " bottom: !!e.querySelector('.panel-bottom') }; }))()")) as List;
  rep.check(
      'header and footer are BODY-ONLY',
      hf.cast<Map<String, dynamic>>().every((r) =>
          r['missing'] != true &&
          r['body'] == true &&
          r['top'] != true &&
          r['bottom'] != true),
      jsonEncode(hf));
}

// ── D ────────────────────────────────────────────────────────────────────────

Future<void> _sectionD(ProbeReport rep, CdpSession p) async {
  rep.section('D. view-transition names stay unique (ADR-0003)');
  final vt = (await p.evaluate(
      "(() => [...document.querySelectorAll('.panel')]"
      ' .map((e) => getComputedStyle(e).viewTransitionName)'
      " .filter((n) => n && n !== 'none'))()")) as List;
  rep.check('no duplicate view-transition-name among panels',
      vt.toSet().length == vt.length, jsonEncode(vt));
}

// ── E ────────────────────────────────────────────────────────────────────────

Future<void> _sectionE(ProbeReport rep, CdpSession p) async {
  rep.section('E. header chrome survived the body wrapper');
  final head = (await p.evaluate(
      "(() => { const b = document.querySelector('.panel-header > .panel-body');"
      ' if (!b) return { missing: true };'
      ' const cs = getComputedStyle(b);'
      " const brand = document.querySelector('.shell-brand')?.getBoundingClientRect();"
      ' return { dir: cs.flexDirection, items: b.children.length,'
      ' brandVisible: !!brand && brand.width > 0,'
      " bg: getComputedStyle(document.querySelector('.panel-header')).backgroundColor };"
      ' })()')) as Map<String, dynamic>;

  rep.check('header body is a horizontal row', head['dir'] == 'row',
      jsonEncode(head));
  rep.check('header still has its chrome children',
      head['items'] is num && (head['items'] as num) > 3,
      'children=${jsUndefined(head['items'])}');
  rep.check('brand is visible', head['brandVisible'] == true);
  // The predicate lives in Dart rather than as a regex literal inside the JS
  // string: escaping `\d` through two layers buys nothing, and the raw value is
  // what the detail wants anyway.
  final bg = head['bg'];
  rep.check(
      'header keeps its translucent fill',
      jsTruthy(bg) && !RegExp(r'^rgb\(\d+, \d+, \d+\)$').hasMatch('$bg'),
      jsTruthy(bg) ? '$bg' : '');
}

// ── F ────────────────────────────────────────────────────────────────────────

Future<void> _sectionF(ProbeReport rep, CdpSession p) async {
  rep.section('F. scrollbar thumb floor');
  // The try/catch is load-bearing: a cross-origin sheet throws on `.cssRules`,
  // and without it the whole evaluate rejects instead of skipping that sheet.
  final thumb = await p.evaluate(r'''(() => {
  const s = [...document.styleSheets].flatMap((sh) => { try { return [...sh.cssRules]; } catch { return []; } })
    .find((r) => r.selectorText === '::-webkit-scrollbar-thumb');
  return s?.style.minHeight || null;
})()''');
  rep.check('thumb has an explicit min-height floor', jsTruthy(thumb),
      thumb == null ? 'null' : '$thumb');
}

// ── G ────────────────────────────────────────────────────────────────────────

Future<void> _sectionG(ProbeReport rep, CdpSession p, ProbeContext ctx) async {
  rep.section('G. the main panel matches its neighbours on a FILE READ too');
  // Not just on the design canvas. main's card is `.panel-viewer` there and
  // `.mp-content` here; if only one carries the chrome, main matches its
  // neighbours on one surface and visibly does not on the other.
  //
  // File links live behind the activity panel's FILES view, not on the canvas.
  await ctx.goto(p, '/design');
  await p.clickSelector('a.panel-views-icon[href="/design/panel/files"]',
      timeout: const Duration(seconds: 2));
  // The `.mjs` slept 700ms here. Wait for the thing about to be read instead —
  // with no report, because "no file link on this surface" is a legitimate
  // outcome the skip below reports, not a settling failure worth a [warn].
  await probeWaitFor(p, 'document.querySelector(${jsonEncode(_fileLinkSel)})',
      timeout: const Duration(seconds: 3));
  final file = await p.evaluate(
      '(() => { const a = document.querySelector(${jsonEncode(_fileLinkSel)});'
      " return a ? (a.getAttribute('href') || a.getAttribute('hx-get')) : null; })()");
  if (file is! String || file.isEmpty) {
    rep.skip('no file link on this surface');
    return;
  }
  await ctx.goto(p, file);
  final r = (await p.evaluate(
      "(() => { const mc = document.querySelector('.mp-content');"
      " const cp = document.querySelector('.panel-composer');"
      ' if (!mc || !cp) return { missing: true };'
      ' return { mc: getComputedStyle(mc).boxShadow, cp: getComputedStyle(cp).boxShadow,'
      " passthrough: !!document.querySelector('.mp-content > .evidence-artifact') }; })()"))
      as Map<String, dynamic>;
  rep.check(
      'a file read gives main the same shadow as the composer',
      r['missing'] != true && (r['passthrough'] == true || r['mc'] == r['cp']),
      jsonEncode(r));
}

// ── H ────────────────────────────────────────────────────────────────────────

Future<void> _sectionH(ProbeReport rep, CdpSession p, ProbeContext ctx) async {
  rep.section('H. header menus are not clipped by the panel card');
  // `.panel` sets overflow:hidden so tall panels scroll inside their rounded
  // corners. The header is exactly --nav-h tall and its two <details> menus open
  // DOWNWARD out of that box — and they only exist at <=839px, where they ARE
  // the navigation. Inheriting the clip kills small-screen nav while every
  // desktop render still looks perfect.
  for (final w in [599, 800]) {
    await p.setViewport(w, 900);
    await ctx.goto(p, '/design');
    final r = (await p.evaluate(r'''(() => {
  const head = document.querySelector('.panel-header');
  const hb = head.getBoundingClientRect();
  const out = [];
  for (const d of head.querySelectorAll('details')) {
    d.open = true;
    const menu = d.querySelector('.drawer-panel, .overflow-menu');
    if (!menu) continue;
    const m = menu.getBoundingClientRect();
    const cs = getComputedStyle(menu);
    out.push({ cls: menu.className, h: Math.round(m.height),
      spills: Math.round(m.bottom) > Math.round(hb.bottom),
      visible: cs.display !== 'none' && cs.visibility !== 'hidden' && m.height > 0 });
    d.open = false;
  }
  return { headOverflow: getComputedStyle(head).overflow, menus: out };
})()''')) as Map<String, dynamic>;
    final menus = (r['menus'] as List).cast<Map<String, dynamic>>();
    rep.check('@${w}px header does not clip its own box',
        r['headOverflow'] == 'visible', '${r['headOverflow']}');
    rep.check(
        '@${w}px every header menu renders with real height',
        menus.isNotEmpty && menus.every((m) => m['visible'] == true),
        jsonEncode(menus));
  }
}

// ── I ────────────────────────────────────────────────────────────────────────

Future<void> _sectionI(ProbeReport rep, CdpSession p, ProbeContext ctx) async {
  rep.section('I. the side panels shed their desktop width below 840px');
  // The composer and the activity panel carry a fixed width, a floor and a
  // shared 500px cap on desktop. Below 840px they stack one at a time and must
  // release all three — and the @media rule that releases them lost on source
  // order twice over: `.panel-activity` is declared later in panels.css, and
  // `.panel-composer` is declared in composer.css, which loads after it. So the
  // rule silently did nothing and the composer sat at its 390px desktop width
  // inside a ~700px column. Desktop rendered perfectly throughout, which is why
  // this is asserted rather than eyeballed.
  for (final vw in [1900, 839, 800, 599]) {
    await p.setViewport(vw, 900);
    for (final role in ['composer', 'activity']) {
      await ctx.goto(p, '/design?panel=$role');
      final sel = jsonEncode('.panel-$role');
      final r = (await p.evaluate(
          "(() => { const row = document.querySelector('.panels');"
          ' const e = document.querySelector($sel);'
          ' if (!e || !row) return null;'
          ' const cs = getComputedStyle(e);'
          ' const rs = getComputedStyle(row);'
          ' const inner = row.getBoundingClientRect().width'
          ' - parseFloat(rs.paddingLeft) - parseFloat(rs.paddingRight);'
          ' return { w: e.getBoundingClientRect().width, inner,'
          ' min: cs.minWidth, max: cs.maxWidth }; })()')) as Map<String, dynamic>?;
      if (r == null) {
        rep.check('@${vw}px $role panel present', false, 'not found');
        continue;
      }
      if (vw < 840) {
        // A mismatch here means a desktop width leaked past the media query.
        rep.check(
            '@${vw}px $role fills the stacked column',
            ((r['w'] as num) - (r['inner'] as num)).abs() <= 2,
            'panel=${(r['w'] as num).round()} column=${(r['inner'] as num).round()}');
        rep.check(
            '@${vw}px $role releases its floor and cap',
            jsParseFloat(r['min']) == 0 && r['max'] == 'none',
            'min=${r['min']} max=${r['max']}');
      } else {
        rep.check('@${vw}px $role keeps the shared 500px cap',
            r['max'] == '500px', 'max=${r['max']}');
      }
    }
  }
  // Both side panels cap at the SAME width — the whole point of --panel-max-w.
  await p.setViewport(1900, 1000);
  await ctx.goto(p, '/design');
  final caps = (await p.evaluate(
      "(() => ['.panel-composer', '.panel-activity']"
      ' .map((s) => getComputedStyle(document.querySelector(s)).maxWidth))()')) as List;
  rep.check('composer and activity share ONE ceiling', caps.toSet().length == 1,
      jsonEncode(caps));
}

// ── J ────────────────────────────────────────────────────────────────────────

Future<void> _sectionJ(ProbeReport rep, CdpSession p, ProbeContext ctx) async {
  rep.section('J. the main panel FILLS its slot on every shell');
  // THE BUG THIS CATCHES: `.step-stage` is `.mp-content` — the main panel's own
  // card — and it carried `max-width: 44rem; margin: 0 auto`. So on intake the
  // card shrank to 44rem and floated mid-slot with ~200px of dead space either
  // side, while the design shell's card filled the same slot edge to edge. Two
  // shells, two visibly different main panels, from one property on the wrong
  // element. The rule: the CARD fills the slot; the reading measure belongs to
  // the CONTENT inside it.
  //
  // Asserted against the SLOT, not against a number: the slot is whatever the
  // composer and the activity panel leave behind, so this keeps holding when a
  // side panel is resized, and it is the same check on a shell that renders no
  // side panels at all (the card then takes the whole row).
  for (final route in ['/intake', '/design', '/build']) {
    await ctx.goto(p, route);
    final r = (await p.evaluate(r'''(() => {
  const slot = document.querySelector('.panel-main');
  const card = slot && slot.querySelector('.panel-viewer, .mp-content');
  if (!slot || !card) return null;
  const measured = document.querySelector('.artifact-lede');
  return { slot: slot.getBoundingClientRect().width,
           card: card.getBoundingClientRect().width,
           lede: measured ? measured.getBoundingClientRect().width : null };
})()''')) as Map<String, dynamic>?;
    if (r == null) {
      rep.check('$route: main panel has a card', false, 'slot or card missing');
      continue;
    }
    rep.check(
        '$route: the card fills the main slot',
        ((r['card'] as num) - (r['slot'] as num)).abs() <= 2,
        'card=${(r['card'] as num).round()} slot=${(r['slot'] as num).round()}');
    // The payoff for capping with a grid track instead of `> * { max-width }`:
    // a child's own, narrower measure survives. 40rem = 640px at the 16px root.
    final lede = r['lede'];
    if (lede != null) {
      rep.check('$route: content keeps its own narrower measure',
          (lede as num).round() == 640, '.artifact-lede=${lede.round()} (want 640)');
    }
  }
  // Same slot, same card width, whatever the shell — the user-visible claim.
  final cards = <Object?>[];
  for (final route in ['/intake', '/design']) {
    await ctx.goto(p, route);
    cards.add(await p.evaluate(
        "(() => { const c = document.querySelector('.panel-main .panel-viewer,"
        " .panel-main .mp-content');"
        ' return c ? Math.round(c.getBoundingClientRect().width) : null; })()'));
  }
  rep.check('intake and design main panels are the SAME width',
      cards[0] != null && cards[0] == cards[1], jsonEncode(cards));
}

// ── K ────────────────────────────────────────────────────────────────────────

Future<void> _sectionK(ProbeReport rep, CdpSession p, ProbeContext ctx) async {
  rep.section('K. the page never scrolls; the panels do');
  // THE BUG THIS CATCHES: the shell was `min-height: 100dvh` with the panels row
  // sized `calc(100dvh - var(--nav-h) - var(--tl-h))` — a height derived from
  // tokens describing two SIBLINGS the row does not own. `--tl-h` measures
  // .timeline, the strip; the footer PANEL around it adds a border, so the
  // column summed to 100.97dvh. One pixel: a real document scrollbar, and far
  // too small to read as anything but a rendering artefact.
  //
  // Asserted as `scrollHeight === clientHeight`, which catches ANY overflow,
  // not the specific pixel — the row is flex-sized now precisely so no future
  // chrome change can re-derive itself out of sync.
  await p.setViewport(1900, 1000);
  // Section G opened a FILE into the main panel, and which surface /design shows
  // is server-side session state — so by now /design renders that read, not the
  // canvas, and the reachability check below would measure a doc with nothing to
  // scroll and blame the layout. Back out of it first: `.mp-file-back` is the
  // file view's own close affordance, so this restores whatever surface the
  // shell was on rather than assuming one.
  // (The .mjs comment credits "Section D" for the file read. It is G — the
  // dependency is real, the label was wrong.)
  await ctx.goto(p, '/design');
  final back = await p.evaluate(
      "(() => { const a = document.querySelector('.mp-file-back');"
      " return a ? a.getAttribute('href') : null; })()");
  if (back is String && back.isNotEmpty) await ctx.goto(p, back);

  for (final route in ['/intake', '/design', '/build']) {
    await ctx.goto(p, route);
    final r = (await p.evaluate(r'''(() => {
  const de = document.documentElement, f = document.querySelector('#panel-footer');
  const inner = [...document.querySelectorAll('.panels *')]
    .filter((e) => e.scrollHeight > e.clientHeight + 1).length;
  return { scrollH: de.scrollHeight, clientH: de.clientHeight, inner,
           tallest: Math.max(0, ...[...document.querySelectorAll('.panels *')]
             .map((e) => e.scrollHeight - e.clientHeight)),
           footerOnScreen: f ? Math.round(f.getBoundingClientRect().bottom) <= window.innerHeight : null };
})()''')) as Map<String, dynamic>;
    rep.check('$route: the page cannot scroll', r['scrollH'] == r['clientH'],
        'document ${r['scrollH']}/${r['clientH']}');
    rep.check('$route: the footer stays on screen', r['footerOnScreen'] != false,
        'a scrolling page drags the chrome out of view');
    // THE LOCK MUST NOT BE A CLIP. /design carries far more content than the
    // viewport — its canvas alone runs ~9× — so if the page stops scrolling and
    // nothing inside scrolls either, that content is simply unreachable.
    // Asserted on "some container inside .panels", NOT on .dv-flow-canvas by
    // name: which lens /design renders is session state that earlier sections
    // change, and a probe that hard-codes one lens' class reports a null and
    // blames the layout. The invariant is that the overflow moved INTO a panel,
    // not which element caught it.
    if (route == '/design') {
      rep.check(
          'the overflow moved into a panel, not off the page',
          (r['inner'] as num) >= 1 && (r['tallest'] as num) > 500,
          "${r['inner']} inner scroller(s), tallest overflow ${r['tallest']}px");
    }
  }

  // And the release below 840px must be LIVE, not dead — the stacked layout
  // hands scrolling BACK to the page (.mp-content gives up its own overflow
  // down there), so a lock left on would clip whatever did not fit. A dead
  // media rule is this file's recurring failure mode; assert the computed value.
  for (final w in [839, 599]) {
    await p.setViewport(w, 700);
    await ctx.goto(p, '/intake');
    final r = (await p.evaluate(
        "(() => { const app = document.querySelector('#app');"
        ' return { overflow: getComputedStyle(app).overflowY,'
        ' minH: getComputedStyle(app).minHeight }; })()')) as Map<String, dynamic>;
    rep.check('@${w}px the page is the scroller again',
        r['overflow'] == 'visible', "#app overflow-y=${r['overflow']}");
    rep.check('@${w}px the shell still fills the viewport',
        (jsParseFloat(r['minH']) ?? double.nan) >= 699, 'min-height=${r['minH']}');
  }
}

// ── L ────────────────────────────────────────────────────────────────────────

Future<void> _sectionL(ProbeReport rep, ProbeContext ctx) async {
  rep.section('L. the chip contract holds (D2)');
  // THE BUG THIS CATCHES: .chip's box model (inline-flex, radius 999px, inset
  // box-shadow border, never a real border) lives in ONE file, widgets.css —
  // every one of the 11 migrated classes is now a thin tone hook that assumes
  // that base is already on the element. If widgets.css stopped loading (link
  // order regression, a typo'd href, base.html losing the tag), every chip on
  // the page would silently fall back to browser defaults: an unstyled inline
  // span with square corners and no border at all. Nothing throws; it just
  // stops looking like a chip everywhere at once.
  // Sections A-K run their whole sequence on the ONE shared page — by the time
  // L runs, that page's session state may carry selection left over from
  // earlier sections (e.g. G's "file read" picks a specific artifact), which
  // changes what /design shows regardless of viewport. Use a fresh, isolated
  // page so L always sees the same default /design view.
  //
  // "Fresh page" is where Playwright and CDP part company, and the difference
  // is not cosmetic. `browser.newPage()` opens a new browser CONTEXT — its own
  // cookie jar and its own storage. `Target.createTarget` (what `newPage` is
  // built on here) opens a tab in the DEFAULT context, so the new page carries
  // the session cookie the earlier sections have been mutating: /design renders
  // G's file read instead of the canvas, and L counted 4 chips where the .mjs
  // counts 25 — a coverage FAIL that is an artefact of the port, not the app.
  // Clearing the jar and the origin's storage buys back the isolation the
  // section's own comment is asking for, without a new context primitive.
  //
  // That clear is BROWSER-WIDE, not page-scoped — it resets the session the
  // shared A–K page is holding too. Safe only because L runs last and nothing
  // asserts on that page afterwards. A section M added below this one would
  // measure a logged-out shell and blame the layout; it belongs above L, or L
  // needs a real fresh context first.
  final lp = await ctx.newPage(width: 1400, height: 1000);
  await lp.send('Network.clearBrowserCookies');
  await lp.send('Storage.clearDataForOrigin',
      {'origin': ctx.base, 'storageTypes': 'all'});
  await ctx.goto(lp, '/design');
  final chips =
      ((await lp.evaluate(_chipContract)) as List).cast<Map<String, dynamic>>();

  rep.check('at least one .chip renders on /design', chips.isNotEmpty,
      'found ${chips.length}');
  rep.check(
      'coverage: at least 20 .chip instances render (not a viewport fluke)',
      chips.length >= 20,
      'found only ${chips.length} — panels that carry chips may not be'
      ' rendering at this viewport');
  // A .chip that is itself a flex/grid item gets its outer display "blockified"
  // per the CSS Display spec — inline-flex resolves to flex in getComputedStyle
  // even though the authored rule (and the actual box model) is inline-flex.
  // That's expected here since nearly every chip sits inside a flex toolbar/row;
  // accept both keywords as passing and rely on the radius/border/shadow checks
  // below (plus the mutation test) to prove the box model is really from
  // widgets.css and not a spec-mandated relabeling of a correctly-styled chip.
  rep.check(
      'every .chip resolves to a flex box (inline-flex, blockified to flex when'
      ' a flex/grid item)',
      chips.every(_isFlexBox),
      jsonEncode(chips
          .where((c) => !_isFlexBox(c))
          .map((c) => "${c['cls']}=${c['display']}")
          .toList()));
  rep.check(
      'every .chip is a full pill (radius: 999px)',
      chips.every((c) => c['radius'] == '999px'),
      jsonEncode(chips
          .where((c) => c['radius'] != '999px')
          .map((c) => "${c['cls']}=${c['radius']}")
          .toList()));
  rep.check(
      'no .chip carries a real border (inset box-shadow only)',
      chips.every((c) => c['borderW'] == '0px'),
      jsonEncode(chips
          .where((c) => c['borderW'] != '0px')
          .map((c) => "${c['cls']}=${c['borderW']}")
          .toList()));

  // MUTATION TEST: prove the checks above are actually exercising widgets.css
  // and not just restating a browser default that would pass either way. Kill
  // the stylesheet in-page and require the SAME assertion to flip to failing.
  final killed = await lp.evaluate(r'''(() => {
  const link = [...document.querySelectorAll('link[rel=stylesheet]')].find((l) => l.href.includes('widgets.css'));
  if (!link) return false;
  link.disabled = true;
  return true;
})()''');
  if (killed != true) {
    rep.check('mutation test: widgets.css link found to disable', false,
        'no <link> with widgets.css — cannot prove the check is live');
  } else {
    final mutated =
        ((await lp.evaluate(_chipContract)) as List).cast<Map<String, dynamic>>();
    // radius/borderW alone are true for a bare unstyled span too, so require
    // the flex layout to also survive: a plain span reverts to display:inline
    // the moment widgets.css stops applying.
    final stillPills = mutated.isNotEmpty &&
        mutated.every((c) =>
            c['radius'] == '999px' && c['borderW'] == '0px' && _isFlexBox(c));
    rep.check(
        'mutation test: killing widgets.css breaks the pill contract (proves L'
        ' is not vacuous)',
        !stillPills,
        stillPills
            ? 'chips STILL look like pills with widgets.css disabled — this'
                ' section is not testing what it claims to'
            : 'confirmed: chips lost their box model');
  }

  await ctx.closePage(lp);
}

// ── helpers ──────────────────────────────────────────────────────────────────

/// The blockification allowance: `inline-flex` resolves to `flex` in
/// `getComputedStyle` when the chip is itself a flex/grid item.
bool _isFlexBox(Map<String, dynamic> c) =>
    c['display'] == 'inline-flex' || c['display'] == 'flex';

// These four are the port's parity contract with JavaScript, and they are
// public so `test/probe_panel_contract_test.dart` can hold them to it. Each one
// exists because the obvious Dart equivalent is subtly different, and the
// difference reaches the output: a wrong `jsParseFloat` inverts a check, a
// wrong `jsNum` prints `640.0` where the .mjs prints `640`.

/// JavaScript truthiness for a value that crossed the CDP boundary — `null`,
/// `false`, `0` and `''` are all falsy there, and the `.mjs` relies on it both
/// for predicates and for whether a detail is printed at all.
bool jsTruthy(Object? v) =>
    v != null && v != false && v != 0 && v != '' && v != 0.0;

/// JS number formatting: a whole double prints without the `.0` Dart adds.
/// Non-numbers stringify unchanged.
String jsNum(Object v) {
  if (v is num && v.isFinite && v == v.roundToDouble()) {
    return v.toInt().toString();
  }
  return '$v';
}

/// JS template-literal rendering of an optional-chained miss: `null?.w` is
/// `undefined`, and the `.mjs` details print that word.
String jsUndefined(Object? v) => v == null ? 'undefined' : jsNum(v);

/// JS `parseFloat` — the leading numeric prefix of a CSS value like `0px`, or
/// null where JS would produce NaN. `double.tryParse('0px')` is null, which
/// would silently invert `parseFloat(min) === 0` from "released" to "not".
double? jsParseFloat(Object? v) {
  if (v is num) return v.toDouble();
  if (v is! String) return null;
  final m =
      RegExp(r'^\s*[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?').firstMatch(v);
  if (m == null) return null;
  return double.tryParse(m.group(0)!.trim());
}
