// probe-boost — boosted MPA inside generated screens: still tiles stay
// script-free, a live tile boosts and keeps in-frame navigation
// same-document.
//
// Dart port of `tools/probe-boost.mjs` (7 checks, 3 sections). Read-only:
// nothing here submits or mutates project state.

import 'package:appboxd/probes/probe_base.dart';

const String _stillTile = '.dv-tile[data-id="portalo.cart"] iframe';
const String _liveSel = '.dv-tile[data-id="portalo.home"] iframe';
const String _armLink = '.dv-tile[data-id="portalo.home"] a[hx-get*="step="]';
const String _inFrameLink = 'a[href*="portalo.category"]';

const Probe boostProbe = Probe(
  name: 'boost',
  summary:
      'static canvas tiles stay script-free; a live tile boosts and keeps in-frame navigation same-document',
  mutates: false,
  body: _run,
);

Future<void> _run(ProbeContext ctx) async {
  final page = await ctx.newPage();
  await ctx.goto(page, '/design');
  await probeWaitFor(
    page,
    "!!document.querySelector('$_stillTile')",
    label: 'the canvas tiles',
    timeout: const Duration(seconds: 15),
    report: ctx.report,
  );

  ctx.report.section('still tiles stay script-free');
  final stillFrame = await page.frameForSelector(_stillTile);
  if (stillFrame == null) {
    throw StateError('no static canvas tile at $_stillTile');
  }
  final stillNoHtmx =
      await page.evaluateInFrame(stillFrame, "typeof window.htmx === 'undefined'");
  ctx.report.check('static canvas tile does NOT load htmx', stillNoHtmx == true);

  ctx.report.section('live tile is boosted');
  await page.evaluate(
      "window.htmx.ajax('GET', '/design/viewer?mode=flows', { target: '#design-viewer', swap: 'morph:outerHTML' })");
  await probeWaitFor(
    page,
    "!!document.querySelector('$_armLink')",
    label: 'the flows lens + its arm control',
    report: ctx.report,
  );
  // Synthetic: the .mjs original clicks via $eval(el => el.click()), a
  // direct DOM click, not real pointer simulation.
  await page.clickSelector(_armLink, synthetic: true);
  // Benign timing race, tolerated as a warn-not-fail by the .mjs original:
  // proceed regardless — the checks below report the real state either way.
  await probeWaitFor(
    page,
    r'''(() => {
      const f = document.querySelector('.dv-tile[data-id="portalo.home"] iframe');
      return !!f && /live=|step=/.test(f.getAttribute('src') || '');
    })()''',
    label: 'the home tile to become live',
    report: ctx.report,
  );
  var liveFrame = await page.frameForSelector(_liveSel);
  if (liveFrame == null) {
    throw StateError('no live iframe at $_liveSel after arming');
  }
  final src =
      await page.evaluate("document.querySelector('$_liveSel').getAttribute('src')");
  ctx.report.out.writeln('  src: $src');
  final loadsHtmx =
      await page.evaluateInFrame(liveFrame, "typeof window.htmx !== 'undefined'");
  ctx.report.check('live tile loads htmx', loadsHtmx == true);
  final hasBoost =
      await page.evaluateInFrame(liveFrame, "document.body.hasAttribute('hx-boost')");
  ctx.report.check('body carries hx-boost', hasBoost == true);

  ctx.report.section('navigate inside: boosted swap, not a document load');
  await page.evaluateInFrame(liveFrame,
      "window.__tok='SURVIVE'; document.documentElement.dataset.tok='SURVIVE';");
  final before = ((await page.evaluateInFrame(liveFrame, 'location.href')) as String)
      .replaceFirst(ctx.base, '');
  final hasLink = (await page.evaluateInFrame(
          liveFrame, "document.querySelector('$_inFrameLink') !== null")) ==
      true;
  ctx.report.check('found in-frame link', hasLink);
  if (hasLink) {
    // Non-synthetic: the .mjs original clicks a real Playwright ElementHandle
    // here, which does hit-testing.
    await page.clickSelectorInFrame(liveFrame, _inFrameLink);
    // Replaces the .mjs's hand-rolled 150ms poll loop: waitForFunctionInFrame
    // is content with a plain boolean expression, no `!!(...)` wrapping.
    await page.waitForFunctionInFrame(
      liveFrame,
      "location.href.includes('portalo.category')",
      timeout: const Duration(seconds: 8),
    );
    liveFrame = await page.frameForSelector(_liveSel);
    if (liveFrame == null) {
      throw StateError('no live iframe at $_liveSel after the in-frame navigation');
    }
    final after = ((await page.evaluateInFrame(liveFrame, 'location.href')) as String)
        .replaceFirst(ctx.base, '');
    final tok = await page.evaluateInFrame(liveFrame, 'window.__tok || null');
    ctx.report.out.writeln('   $before -> $after');
    ctx.report.check('screen actually changed', after.contains('portalo.category'), after);
    ctx.report.check('same document (boosted, no full load)', tok == 'SURVIVE',
        'window token=$tok');
    ctx.report.check('inspect param rides along in links',
        after.contains('vp=') && !after.contains('undefined'), after);
  }

  await ctx.closePage(page);
}
