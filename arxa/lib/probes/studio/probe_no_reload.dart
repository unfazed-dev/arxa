// probe-no-reload — acceptance probe for the no-reload work.
//   A  an unrelated interaction must not destroy the viewer's iframes
//   B  navigation done INSIDE a live tile must survive an unrelated
//      interaction  <-- the user's complaint
//   C  browser/morph capability facts
//   D  morph hazards: duplicate ids, <details> open state, typed text, web
//      components
//
// Dart port of `archives/tooling-pre-dart/tools/studio-probes/probe-no-reload.mjs` (10 checks in the pass case, one
// page for the whole run — state has to carry across sections).

import 'dart:convert';

import 'package:arxa/probes/probe_base.dart';

const String _mark = r'''(() => { const f=[...document.querySelectorAll('iframe')]; f.forEach((x,i)=>x.__probe='p'+i); return f.length; })()''';
const String _survivors = r'''(() => { const f=[...document.querySelectorAll('iframe')]; return {total:f.length, marked:f.filter(x=>x.__probe!==undefined).length}; })()''';
const String _dupIds = r'''(() => {
  const seen={}, dup=[];
  for (const el of document.querySelectorAll('[id]')) { if (seen[el.id]) dup.push(el.id); seen[el.id]=1; }
  return [...new Set(dup)];
})()''';

const String _liveSel = '.dv-tile[data-id="portalo.home"] iframe';
const String _inFrameLink = 'a[href*="portalo.category"]';

const Probe noReloadProbe = Probe(
  name: 'no-reload',
  summary:
      'an unrelated pin must not destroy iframes or lose in-frame navigation',
  // Sections A, D2 and B click controls that POST (`hx-get*="context"`, an
  // in-tile navigation). The .mjs original never guards this — see
  // docs/probes-capability-map.md, "Registry — adding a probe (wave C)": the
  // port declares the guard anyway, which is a strengthening, not drift.
  mutates: true,
  body: _run,
);

Future<void> _run(ProbeContext ctx) async {
  final page = await ctx.newPage();
  await ctx.goto(page, '/design');
  await page.waitForSelector('iframe.dv-tile-frame',
      timeout: const Duration(seconds: 15));
  await waitQuiet(page, report: ctx.report);

  ctx.report.section('C. capability');
  // htmx4 ships morph in core (config.morphSkip/morphScanLimit, swap token
  // `outerMorph`) — there is no idiomorph extension and no `hx-ext` wiring
  // anymore. The old assertion encoded the v2 stack; asserting it against
  // htmx4 fails on every correctly-served page.
  final morphReady = await page.evaluate(
      "!!(window.htmx && htmx.config && 'morphSkip' in htmx.config && 'morphScanLimit' in htmx.config)");
  final htmxVersion = await page.evaluate('window.htmx && htmx.version');
  ctx.report.out.writeln('  htmx            : ${htmxVersion ?? 'undefined'}');
  final idiomorphType = await page.evaluate('typeof Idiomorph');
  ctx.report.out.writeln('  Idiomorph loaded: $idiomorphType (htmx4 core morph needs none)');
  final moveBefore = await page.evaluate("'moveBefore' in Element.prototype");
  ctx.report.out.writeln('  Element.moveBefore: $moveBefore');
  ctx.report.check('htmx4 core morph available', morphReady == true);

  ctx.report.section('D1. duplicate ids (morph correctness precondition)');
  final dups =
      ((await page.evaluate(_dupIds)) as List?)?.cast<String>() ?? const [];
  ctx.report.check('no duplicate ids in /design', dups.isEmpty,
      dups.isNotEmpty ? dups.take(6).join(', ') : '');

  // Started here, not before goto: the only checks that read it (E) exercise
  // the `/context/` GET the pin control fires, which first happens in A —
  // recording from the initial page load is unnecessary traffic to fetch and
  // buffer.
  final bodies = await page.recordNetworkBodies();

  ctx.report.section('A. does an unrelated interaction destroy the iframes?');
  final beforeCount = ((await page.evaluate(_mark)) as num).toInt();
  var navCount = 0;
  final mainFrameId = (await page.frames()).first.id;
  final navSub = page.on('Page.frameNavigated').listen((e) {
    final id = '${(e.params['frame'] as Map?)?['id']}';
    if (id != mainFrameId) navCount++;
  });
  // Synthetic: the tile tool rail is hover-revealed, so a real pointer cannot
  // reach it in a headless run.
  await page.clickSelector('.dv-tile .dv-tile-tools a[hx-get*="context"]',
      synthetic: true);
  await waitQuiet(page, report: ctx.report);
  await navSub.cancel();
  final afterRaw = (await page.evaluate(_survivors)) as Map;
  final afterMarked = (afterRaw['marked'] as num).toInt();
  ctx.report.out.writeln(
      '  iframes $beforeCount -> surviving DOM nodes $afterMarked, iframe navigations $navCount');
  ctx.report.check('iframes survive as the same DOM nodes',
      afterMarked >= beforeCount - 1, '$afterMarked/$beforeCount');
  ctx.report
      .check('no iframe re-navigation', navCount == 0, '$navCount navigations');

  ctx.report.section('D2. node identity + typed text survive a swap');
  final hadDetails = (await page.evaluate(r'''(() => { const d=document.querySelector('details.dv-tool-menu'); if(!d) return false; d.__probeNode=1; return true; })()''')) ==
      true;
  await page.evaluate(r'''(() => { const t=document.querySelector('.composer-card textarea, textarea[name="text"]'); if(t){ t.value='DRAFT-KEEP-ME'; } })()''');
  final hadTextarea =
      (await page.evaluate('''!!document.querySelector('textarea[name="text"]')''')) ==
          true;
  await page.clickSelector(
      '.dv-tile[data-id="portalo.cart"] .dv-tile-tools a[hx-get*="context"]',
      synthetic: true);
  await waitQuiet(page, report: ctx.report);
  final detailsSameNode = hadDetails &&
      (await page.evaluate(r'''(()=>{const d=document.querySelector('details.dv-tool-menu'); return !!(d&&d.__probeNode===1);})()''')) ==
          true;
  final textKept = hadTextarea &&
      (await page.evaluate(r'''(()=>{const t=document.querySelector('textarea[name="text"]'); return !!(t&&t.value==='DRAFT-KEEP-ME');})()''')) ==
          true;
  if (hadDetails) {
    ctx.report.check('<details> menu survives as the same node', detailsSameNode);
  }
  if (hadTextarea) {
    ctx.report.check('typed composer draft preserved', textKept);
  }

  ctx.report.section("B. navigation INSIDE a live tile survives (THE complaint)");
  await page.evaluate(
      "window.htmx.ajax('GET', '/design/viewer?mode=flows', { target: '#design-viewer', swap: 'morph:outerHTML' })");
  await waitQuiet(page, report: ctx.report);
  await page.clickSelector('.dv-tile[data-id="portalo.home"] a[hx-get*="step="]',
      synthetic: true);
  await waitQuiet(page, report: ctx.report);

  // Unguarded: the .mjs original has no null check resolving this iframe
  // either (`(await page.$(liveSel)).contentFrame()` throws on a miss), so a
  // miss here aborts the run the same way — same failure shape, same count.
  var frame = await page.frameForSelector(_liveSel);
  if (frame == null) {
    throw StateError('no live iframe at $_liveSel — the home tile never armed');
  }
  final startUrl = ((await page.evaluateInFrame(frame, 'location.href')) as String)
      .replaceFirst(ctx.base, '');
  ctx.report.out.writeln('  starts at : $startUrl');
  final hasLink = (await page.evaluateInFrame(frame,
          "document.querySelector(${jsonEncode(_inFrameLink)}) !== null")) ==
      true;
  if (!hasLink) {
    ctx.report.check('found in-frame link to navigate', false);
  } else {
    // Non-synthetic: the .mjs original clicks a real Playwright ElementHandle
    // here, which does hit-testing — the assertion below depends on it.
    await page.clickSelectorInFrame(frame, _inFrameLink);
    await waitQuiet(page, report: ctx.report);
    frame = await page.frameForSelector(_liveSel);
    if (frame == null) {
      throw StateError('no live iframe at $_liveSel after the in-frame navigation');
    }
    final afterNav = ((await page.evaluateInFrame(frame, 'location.href')) as String)
        .replaceFirst(ctx.base, '');
    ctx.report.out.writeln('  after nav : $afterNav');
    // Synthetic: same hover-revealed tile tool rail as section A.
    await page.clickSelector(
        '.dv-tile[data-id="portalo.cart"] .dv-tile-tools a[hx-get*="context"]',
        synthetic: true);
    await waitQuiet(page, report: ctx.report);
    frame = await page.frameForSelector(_liveSel);
    if (frame == null) {
      throw StateError('no live iframe at $_liveSel after the unrelated pin');
    }
    final ended = ((await page.evaluateInFrame(frame, 'location.href')) as String)
        .replaceFirst(ctx.base, '');
    ctx.report.out.writeln('  after unrelated pin : $ended');
    ctx.report.check("live tile kept the user's navigation",
        ended.contains('portalo.category'), ended);
  }

  ctx.report.section('D3. web components still upgraded after a morph');
  final wc = (await page.evaluate(r'''(() => {
  const names = ['model-viewer','dotlottie-wc'];
  const out = {};
  for (const n of names) {
    const el = document.querySelector(n);
    out[n] = el ? (customElements.get(n) ? 'defined' : 'present-undefined') : 'absent-in-shell';
  }
  return out;
})()''')) as Map;
  ctx.report.out.writeln(
      '   ${jsonEncode(wc)} (shell-level; portalo web components live inside iframes)');

  ctx.report.section('E. pin payload cost');
  // encodedLength (wire bytes), NOT the decoded body length the .mjs
  // original reads — a payload-size ceiling should read what actually
  // crossed the wire, not what gzip decompressed to. Deliberate
  // strengthening; recorded in the capability map.
  final ctxRecords = (await bodies.stop())
      .where((r) => r.url.contains('/context/') && r.encodedLength != null)
      .toList();
  final worstPin = ctxRecords.isEmpty
      ? 0
      : ctxRecords.map((r) => r.encodedLength!).reduce((a, b) => a > b ? a : b);
  ctx.report.out
      .writeln('  pin responses: ${ctxRecords.length}, largest $worstPin bytes');
  if (ctxRecords.isNotEmpty) {
    ctx.report.check('pin response under the 200 KB blow-up ceiling',
        worstPin < 200000, '$worstPin bytes');
  }

  ctx.report.section('page errors');
  final errs = page.pageErrors;
  ctx.report.out
      .writeln(errs.isEmpty ? '  none' : errs.take(5).map((e) => '  ! $e').join('\n'));
  ctx.report.check('no uncaught page errors', errs.isEmpty);

  await ctx.closePage(page);
}
