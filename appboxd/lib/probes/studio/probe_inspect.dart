// probe-inspect — the inspector pane (activity panel, 4th view; D14-D17):
// arm, hover feeds the pane (unlocked), click locks it, a further hover while
// locked changes nothing ("locked wins"), the lock survives a full htmx morph
// of the panel (session state, not DOM state — D16), the pane's own unlock
// button drops the lock and falls back to the last hover, the pin button
// POSTs to chat context WITHOUT reloading the inspected iframe, and a hover
// while the inspector is not the active view is a no-op (204 guard — D14).
//
// Dart port of `archives/tooling-pre-dart/tools/studio-probes/probe-inspect.mjs` (21 checks, 9 sections).
//
// Every hover and click on an element of the inspected SCREEN goes through the
// frame-scoped verbs rather than the parent's `contentDocument`. That is not
// stylistic: the viewer scales its tiles, so an in-frame
// `getBoundingClientRect()` added to the iframe's own rect misses the element
// by the scale factor, and this probe's whole subject is where a real pointer
// landed.

import 'dart:convert';

import 'package:appboxd/cdp.dart';
import 'package:appboxd/probes/probe_base.dart';

const String _tile = '.dv-tile[data-id="portalo.home"]';
const String _code = '#av-list .msg-text code';
const String _unlockBtn = '#av-list button[hx-post*="/design/inspector/unlock"]';
const String _inspectorIcon = 'a.panel-views-icon[href="/design/inspector"]';
const String _screensIcon = 'a.panel-views-icon[href="/design/panel/screens"]';

/// The requests this probe counts. Everything else the studio issues is noise
/// here, and an unfiltered log would bury the three routes under it.
final RegExp _watched = RegExp(r'inspector/(select|unlock)|context/element');

const Probe inspectProbe = Probe(
  name: 'inspect',
  summary: 'inspector pane: arm, hover, lock, morph, pin, unlock, 204 guard',
  // Section 7 pins the inspected element into chat context, which POSTs into
  // whatever project the target is serving. The .mjs original guards this by
  // calling requireDisposableProject; declaring it here gets the same guard
  // from the harness, before Chrome is launched.
  mutates: true,
  body: _run,
);

Future<void> _run(ProbeContext ctx) async {
  final page = await ctx.newPage();

  final reqs = <String>[];
  await page.send('Network.enable');
  page.on('Network.requestWillBeSent').listen((e) {
    final url = '${e.params['request']?['url']}';
    if (!_watched.hasMatch(url)) return;
    reqs.add('${e.params['request']?['method']} '
        '${url.replaceAll(ctx.base, '')}');
  });
  final http4xx = <String>[];
  page.on('Network.responseReceived').listen((e) {
    final res = e.params['response'] as Map<String, dynamic>?;
    final status = (res?['status'] as num?)?.toInt() ?? 0;
    if (status >= 400) {
      http4xx.add('http $status ${'${res?['url']}'.replaceAll(ctx.base, '')}');
    }
  });

  // Every read below lands immediately after an interaction. A flat 700ms was
  // a guess measured on an idle machine; under load the read landed mid-swap
  // and the probe reported regressions that were not there (#48/#50). Waiting
  // for the page to stop changing is correct in both directions: faster when
  // idle, and still correct when the machine is busy.
  Future<void> settle() => waitQuiet(page, report: ctx.report);

  /// Wait for the island to have POSTed, then for the swap it triggers.
  ///
  /// [settle] alone is not enough after a hover, and the reason is specific:
  /// the island posts from a `pointermove` handler, and between the pointer
  /// arriving and the response swapping the panel the DOM does not change at
  /// all. waitQuiet samples that gap, sees two identical samples, and returns
  /// — before the request it is meant to be waiting for has even been sent.
  /// The .mjs original gets away with the same call because Playwright's
  /// `hover()` spends longer on actionability checks than the round trip
  /// takes, which is a race it happens to win rather than a wait.
  Future<void> settleAfterRequest(int before, String what) async {
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (reqs.length <= before && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (reqs.length <= before) {
      ctx.report.warn('no $what request within 8000ms —'
          ' the check below reports the real state');
    }
    await settle();
  }

  await ctx.goto(page, '/design');

  ctx.report.section('1. switch the activity panel to the inspector view');
  await page.clickSelector(_inspectorIcon);
  await settle();
  ctx.report.check(
      'carousel icon is active',
      await page.evaluate(
              '(() => { const e = document.querySelector(${jsonEncode(_inspectorIcon)});'
              " return !!e && e.classList.contains('is-active'); })()") ==
          true);
  ctx.report.check('#av-list is rendered',
      await _present(page, '#panel-activity-body #av-list'));
  // D17 / task #47: screenCardFor falls back to the viewer's active screen
  // (viewerFor's `active`) when inspectorScreenId is unset, so a fresh
  // session shows the screen card the moment the pane opens — nothing has
  // been hovered or locked yet. Was previously dead code (mode was always
  // 'empty' here); this proves the fallback wiring actually renders.
  final screenId = await _text(page, _code);
  ctx.report.check('screen card renders on open (mode: screen, no hover yet)',
      screenId != null, screenId ?? '(none found)');
  ctx.report.check(
      'not shown as locked/element chrome', !await _present(page, _unlockBtn));

  ctx.report.section('2. arm inspect on portalo.home');
  // The tile toolbar is opacity/pointer-events gated behind :hover|:focus-within
  // (viewer.css). Hovering the tile opens that gate; clickSelector then hovers
  // the revealed control and re-measures it before clicking, which is what the
  // .mjs does by hand with an explicit hover to sidestep Playwright's
  // actionability pre-check.
  await page.hoverSelector(_tile);
  await settle();
  await page.clickSelector('$_tile a[hx-get*="inspect="]');
  await settle();
  final doc = await page.frameForSelector('$_tile iframe');
  if (doc == null) {
    throw StateError('no iframe in the portalo.home tile — inspect was never'
        ' armed, so every check below would report a broken inspector when the'
        ' truth is the probe never found the thing it inspects');
  }
  ctx.report.check(
      'iframe armed (data-inspect-armed)',
      await page.evaluateInFrame(
              doc, "document.body.dataset.inspectArmed === 'true'") ==
          true);
  ctx.report.check('inspect.js loaded',
      await page.evaluateInFrame(doc, '!!document._inspect') == true);

  ctx.report
      .section('3. hover [data-el="card:Ceramics"] -> pane shows it, unlocked');
  final reqsBefore3 = reqs.length;
  await page.hoverSelectorInFrame(doc, '[data-el="card:Ceramics"]');
  await settleAfterRequest(reqsBefore3, 'inspector/select');
  ctx.report.check('POST /design/inspector/select fired',
      reqs.any((r) => r.contains('inspector/select')));
  ctx.report.check(
      'pane shows card:Ceramics', await _text(page, _code) == 'card:Ceramics');
  ctx.report
      .check('not shown as locked', !await _present(page, '#av-list .msg.is-active'));

  ctx.report.section('4. click it -> locks the pane');
  final reqsBefore4 = reqs.length;
  await page.clickSelectorInFrame(doc, '[data-el="card:Ceramics"]');
  await settleAfterRequest(reqsBefore4, 'inspector/select (lock)');
  ctx.report.check(
      'pane shows card:Ceramics, locked',
      await _text(page, _code) == 'card:Ceramics' &&
          await _present(page, '#av-list .msg.is-active'));
  ctx.report.check('unlock button present', await _present(page, _unlockBtn));

  ctx.report.section(
      '5. hover a different element while locked -> "locked wins", pane unchanged');
  // tab:Home is a `position: fixed` bottom-tab-bar element; inside the scaled
  // still-preview iframe its fixed containing block is the transformed stub
  // wrapper, which places it below the visible crop — an in-flow card is a
  // reliable second target instead.
  final reqsBefore5 = reqs.length;
  await page.hoverSelectorInFrame(doc, '[data-el="card:Furniture"]');
  await settleAfterRequest(reqsBefore5, 'inspector/select (while locked)');
  ctx.report.check(
      'hover while locked still POSTed (proves the pane is unchanged despite a real request, not a dead hover)',
      reqs.length > reqsBefore5,
      '$reqsBefore5 -> ${reqs.length}');
  ctx.report.check(
      'pane still shows card:Ceramics, still locked',
      await _text(page, _code) == 'card:Ceramics' &&
          await _present(page, '#av-list .msg.is-active'));

  ctx.report.section(
      '6. lock survives a full panel morph (session state, not DOM state — D16)');
  await page.clickSelector(_screensIcon);
  await settle();
  await page.clickSelector(_inspectorIcon);
  await settle();
  ctx.report.check(
      'still locked to card:Ceramics after the round trip',
      await _text(page, _code) == 'card:Ceramics' &&
          await _present(page, '#av-list .msg.is-active'));

  ctx.report.section(
      '7. pin from the pane -> chat context gains the chip, iframe is NOT reloaded');
  final chipsBefore = await _count(page, '.cs-el-chip');
  // The main frame navigating is the page doing its job; a CHILD frame
  // navigating is the inspected iframe reloading, which is the regression.
  final mainFrameId = (await page.frames()).first.id;
  var navs = 0;
  final navSub = page.on('Page.frameNavigated').listen((e) {
    final id = '${(e.params['frame'] as Map?)?['id']}';
    if (id != mainFrameId) navs++;
  });
  const pinBtn =
      '#av-list form[hx-post="/design/chat/context/element"] button[type="submit"]';
  final hasPin = await _present(page, pinBtn);
  ctx.report.check('pin button present', hasPin);
  if (hasPin) {
    await page.clickSelector(pinBtn);
    await waitQuiet(page, report: ctx.report);
  }
  await navSub.cancel();
  final chipsAfter = await _count(page, '.cs-el-chip');
  ctx.report.check('element chip added', chipsAfter > chipsBefore,
      '$chipsBefore -> $chipsAfter');
  ctx.report
      .check('inspected iframe did not navigate', navs == 0, '$navs nav(s)');

  ctx.report.section('8. unlock -> drops the lock, falls back to the last hover');
  final reqsBefore8 = reqs.length;
  await page.clickSelector(_unlockBtn);
  await settleAfterRequest(reqsBefore8, 'inspector/unlock');
  ctx.report.check('POST /design/inspector/unlock fired',
      reqs.any((r) => r.contains('inspector/unlock')));
  ctx.report.check(
      'pane still shows card:Ceramics, no longer locked',
      await _text(page, _code) == 'card:Ceramics' &&
          !await _present(page, '#av-list .msg.is-active'));

  ctx.report.section(
      '9. hover while the inspector is NOT the active view -> 204, no-op');
  await page.clickSelector(_screensIcon);
  await settle();
  final before = await page.evaluate(
      "document.querySelector('#panel-activity-body').innerHTML");
  final reqsBefore9 = reqs.length;
  await page.hoverSelectorInFrame(doc, '[data-el="card:Lighting"]');
  await settleAfterRequest(reqsBefore9, 'inspector/select (inspector inactive)');
  final after = await page.evaluate(
      "document.querySelector('#panel-activity-body').innerHTML");
  // The island posts on every hover regardless of which pane is open — the
  // 204 guard is server-side (prototype_viewmodel.js: inspectorSelect). If the
  // request never fired, "untouched" would be vacuously true with nothing
  // exercised, so assert the POST happened too.
  ctx.report.check(
      'POST /design/inspector/select still fired (proves the guard, not a dead hover)',
      reqs.length > reqsBefore9,
      '$reqsBefore9 -> ${reqs.length}');
  ctx.report
      .check('screens list untouched by the hover (204 no-op)', before == after);

  ctx.report.section('requests seen');
  ctx.report.out.writeln(reqs.isNotEmpty ? '  ${reqs.join('\n  ')}' : '  (none)');
  ctx.report.section('errors');
  final errs = <String>[
    ...page.pageErrors.map((e) => 'page: $e'),
    ...page.consoleErrors
        .map((e) => 'console: ${e.length > 120 ? e.substring(0, 120) : e}'),
    ...http4xx,
  ];
  ctx.report.out
      .writeln(errs.isNotEmpty ? errs.map((e) => '  ! $e').join('\n') : '  none');

  await ctx.closePage(page);
}

Future<bool> _present(CdpSession page, String selector) async =>
    await page.evaluate(
        'document.querySelector(${jsonEncode(selector)}) !== null') ==
    true;

/// Trimmed text of the first [selector], or null when it is not there.
///
/// Null rather than '' so "the pane rendered nothing" and "the pane rendered
/// an empty code element" stay distinguishable — check 3 of section 1 is
/// exactly that distinction.
Future<String?> _text(CdpSession page, String selector) async {
  final v = await page.evaluate(
      '(() => { const e = document.querySelector(${jsonEncode(selector)});'
      ' return e ? e.textContent.trim() : null; })()');
  return v is String ? v : null;
}

Future<int> _count(CdpSession page, String selector) async {
  final n = await page
      .evaluate('document.querySelectorAll(${jsonEncode(selector)}).length');
  return n is num ? n.toInt() : 0;
}
