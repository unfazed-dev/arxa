// probe-widget-tools — the drawer's Tools tab consumes the ONE shared widget
// selection (Screen Reveal-Drawer plan, increment 3).
//
// D5's claim under test is singularity: a selection made anywhere shows up
// everywhere. The strip in the Tools tab posts the SAME /design/widget/select
// route an armed canvas click posts, and the session key it writes
// (d.widgetSel) feeds the drawer's Tools pane — the components column and its
// inline editor slot were removed (increment 5), so the drawer mount is the
// only one; the singularity evidence is now the canvas-side half (section F:
// the same pick arms drag.js's resize handles off the canvas body's
// data-wedit-sel).
//
// D7's claim is honesty: every copy class renders EXACTLY ONE of {an editable
// form, a read-only reason} — never both, never a dead control, never a bare
// nothing. Section D iterates real selections rather than hand-picking one,
// because the honest-fallback branch a probe never visits is the one that
// rots. Nothing here submits a write: the probe proves the controls and the
// refusals render, and the write path itself is the same setWidgetAttr /
// setWidgetText machinery the facade already 400-guards.

import 'package:arxa/probes/probe_base.dart';

const Probe widgetToolsProbe = Probe(
  name: 'widget-tools',
  summary: 'Tools tab: shared selection sync, hierarchy strip, provenance honesty',
  // Selection and drawer tab are session view state only (D8); no attr chip
  // or copy form is ever submitted, so no project file changes.
  mutates: false,
  body: _run,
);

// Same screen pick as probe-reveal-drawer: portalo.auth, slug = dots to dashes.
const _slug = 'portalo-auth';
const _drawerSel = '#dv-drawer-$_slug';
const _triggerSel = '.dv-drawer-toggle[aria-controls="dv-drawer-$_slug"]';
const _toolsTabSel = '#dv-drawer-tab-tools--$_slug';
const _sibSel = '$_drawerSel .dv-tools-sib';

Future<void> _run(ProbeContext ctx) async {
  final page = await ctx.newPage(width: 1800, height: 1100);
  await ctx.goto(page, '/design');
  await probeWaitFor(
    page,
    "document.querySelectorAll('.dv-reveal').length > 0",
    timeout: const Duration(seconds: 15),
    label: 'the reveal-drawer wrappers',
    report: ctx.report,
  );

  ctx.report.section('A. Tools opens empty: strip offered, no editor, honest hint');
  await page.clickSelector(_triggerSel, synthetic: true);
  await probeWaitFor(
    page,
    "document.querySelector('$_triggerSel')?.getAttribute('aria-expanded') === 'true'",
    label: 'the drawer to open',
    report: ctx.report,
  );
  await page.clickSelector(_toolsTabSel, synthetic: true);
  await probeWaitFor(
    page,
    "!!document.querySelector('$_drawerSel .dv-tools')",
    label: 'the Tools pane',
    report: ctx.report,
  );
  final empty = _map(await page.evaluate('''
(() => {
  const aside = document.querySelector('$_drawerSel');
  const sibs = [...aside.querySelectorAll('.dv-tools-sib')];
  return {
    sibs: sibs.length,
    sibsAreButtons: sibs.every((b) => b.tagName === 'BUTTON'),
    card: !!aside.querySelector('.dv-wedit-card'),
    copyForm: !!aside.querySelector('.dv-tools-copy-form'),
    hint: aside.querySelector('.dv-drawer-stub')?.textContent.trim() ?? null,
  };
})()'''));
  ctx.report
    ..check('the hierarchy strip offers this screen\'s widgets',
        (empty['sibs'] is num) && (empty['sibs'] as num) > 0, '${empty['sibs']} chips')
    ..check('strip entries are real buttons', empty['sibsAreButtons'] == true)
    ..check('no editor card before a selection', empty['card'] == false)
    ..check('no copy form before a selection', empty['copyForm'] == false)
    ..check('the empty state says so instead of rendering blank',
        empty['hint'] is String && (empty['hint'] as String).isNotEmpty, '${empty['hint']}');

  ctx.report.section('B. one strip pick renders the drawer editor for that pick');
  final firstKind =
      await page.evaluate("document.querySelector('$_sibSel')?.textContent.trim() ?? ''");
  await page.clickSelector(_sibSel, synthetic: true);
  await probeWaitFor(
    page,
    "!!document.querySelector('$_drawerSel .dv-wedit-card')",
    label: 'the Tools editor to render for the pick',
    report: ctx.report,
  );
  final sync = _map(await page.evaluate('''
(() => {
  const aside = document.querySelector('$_drawerSel');
  const on = aside.querySelector('.dv-tools-sib.on');
  const head = aside.querySelector('.dv-wedit-card .dv-wedit-head b');
  const crumb = aside.querySelector('.dv-tools-crumb');
  return {
    stillOpen: !!aside.closest('.dv-reveal.is-open'),
    onChip: on ? on.textContent.trim() : null,
    head: head ? head.textContent.trim() : null,
    crumb: crumb ? crumb.textContent.trim() : null,
    prov: aside.querySelector('.dv-wedit-prov')?.textContent.trim() ?? null,
  };
})()'''));
  ctx.report
    ..check('the drawer stays out across the selection swap', sync['stillOpen'] == true)
    ..check('the picked chip reads selected', sync['onChip'] == firstKind,
        'chip=${sync['onChip']} picked=$firstKind')
    ..check('the editor head names the same widget',
        sync['head'] is String && firstKind.toString().startsWith('${sync['head']}'),
        'head=${sync['head']}')
    ..check('the breadcrumb carries screen › selection',
        sync['crumb'] is String && (sync['crumb'] as String).contains('portalo.auth'),
        '${sync['crumb']}')
    ..check('provenance stated before any edit (applies-to)',
        sync['prov'] is String && (sync['prov'] as String).isNotEmpty, '${sync['prov']}');

  ctx.report.section('C. contract-declared props are live controls in the drawer');
  final controls = _map(await page.evaluate('''
(() => {
  const card = document.querySelector('$_drawerSel .dv-wedit-card');
  const rows = card ? [...card.querySelectorAll('.dv-wedit-row')] : [];
  const chips = card ? [...card.querySelectorAll('.dv-wedit-step')] : [];
  return {
    rows: rows.length,
    chipsPost: chips.length > 0 && chips.every((b) => (b.getAttribute('hx-post') || '') === '/design/widget/attr'),
  };
})()'''));
  ctx.report
    ..check('pad / gap / resize-x / resize-y rows render', controls['rows'] == 4,
        '${controls['rows']} rows')
    ..check('every step chip posts the provenance-routed attr write',
        controls['chipsPost'] == true);

  ctx.report.section('D. provenance honesty: every selection renders form XOR reason');
  final sibCount = (await page.evaluate(
      "document.querySelectorAll('$_sibSel').length") as num).toInt();
  final probed = sibCount < 5 ? sibCount : 5;
  for (var i = 0; i < probed; i++) {
    // nth-of-type is safe: the chips are the nav's only <button> children.
    final chip = '$_drawerSel .dv-tools-strip button:nth-of-type(${i + 1})';
    await page.clickSelector(chip, synthetic: true);
    await probeWaitFor(
      page,
      "document.querySelector('$chip')?.classList.contains('on') === true",
      label: 'selection ${i + 1} of $probed to land',
      report: ctx.report,
    );
    final copy = _map(await page.evaluate('''
(() => {
  const aside = document.querySelector('$_drawerSel');
  const section = aside.querySelectorAll('.dv-tools-copy');
  const form = aside.querySelector('.dv-tools-copy-form');
  const ro = aside.querySelector('.dv-tools-copy .dv-tools-ro');
  const roRows = aside.querySelectorAll('.dv-tools-ro-attrs .dv-tools-ro-row').length;
  const roNote = !!aside.querySelector('.dv-tools-ro-attrs .dv-tools-ro');
  return {
    sections: section.length,
    form: !!form,
    reason: ro ? ro.textContent.trim() : null,
    roRows,
    roNote,
  };
})()'''));
    final hasForm = copy['form'] == true;
    final hasReason = copy['reason'] is String && (copy['reason'] as String).isNotEmpty;
    ctx.report
      ..check('selection ${i + 1}: one copy section', copy['sections'] == 1,
          '${copy['sections']}')
      ..check(
          'selection ${i + 1}: editable form XOR stated reason',
          hasForm != hasReason,
          hasForm ? 'editable' : 'read-only: ${copy['reason']}')
      ..check(
          'selection ${i + 1}: extra source attrs carry the read-only note iff shown',
          (copy['roRows'] as num? ?? 0) > 0 ? copy['roNote'] == true : copy['roNote'] == false,
          '${copy['roRows']} rows');
  }

  ctx.report.section('E. selection survives a tab round-trip (session state, D8)');
  await page.clickSelector('#dv-drawer-tab-composer--$_slug', synthetic: true);
  await probeWaitFor(
    page,
    "!!document.querySelector('$_drawerSel form.composer')",
    label: 'the Composer tab',
    report: ctx.report,
  );
  await page.clickSelector(_toolsTabSel, synthetic: true);
  await probeWaitFor(
    page,
    "!!document.querySelector('$_drawerSel .dv-tools')",
    label: 'the Tools tab to return',
    report: ctx.report,
  );
  final back = _map(await page.evaluate('''
(() => {
  const aside = document.querySelector('$_drawerSel');
  return {
    onChip: !!aside.querySelector('.dv-tools-sib.on'),
    card: !!aside.querySelector('.dv-wedit-card'),
  };
})()'''));
  ctx.report
    ..check('the selected chip is still selected', back['onChip'] == true)
    ..check('the editor re-renders for the kept selection', back['card'] == true);

  ctx.report.section('F. armed canvas click selects, and drag.js hangs the handles');
  // Replaces tool/shot_increment3.dart (retired with the container): the arm
  // chip → in-frame click → server selection → resize handles chain, end to
  // end. The static half pins drag.js's commit target to the drawer's Tools
  // mount — the old #dv-wedit-<screen> slot is gone, and a commit aimed at it
  // would swap into nothing while reporting success.
  final dragSrc = '${await page.evaluate(
      "fetch('/assets/vendor/drag.js').then((r) => r.text())")}';
  ctx.report
    ..check('drag.js commits into the drawer mount, not the dead slot',
        dragSrc.contains("'#dv-drawer-'") && !dragSrc.contains("'#dv-wedit-'"),
        '${dragSrc.length} bytes')
    ..check('explode.js is no longer served a script tag',
        await page.evaluate(
                "!!document.querySelector('script[src*=\"explode.js\"]')") ==
            false);

  await page.clickSelector('.dv-arm-chip');
  await probeWaitFor(
    page,
    "!!document.querySelector('[data-wedit-armed=\"1\"]')",
    label: 'the canvas to arm',
    report: ctx.report,
  );
  final tileFrame =
      await page.frameForSelector('.dv-tile[data-id="portalo.auth"] iframe');
  if (tileFrame == null) {
    ctx.report.check('the portalo.auth tile frame exists', false);
  } else {
    await page.clickSelectorInFrame(tileFrame, '[data-el]');
    await probeWaitFor(
      page,
      "(document.querySelector('[data-wedit-sel]')?.getAttribute('data-wedit-sel') || '')"
      ".includes('portalo.auth')",
      label: 'the armed click to select server-side',
      report: ctx.report,
    );
    await probeWaitFor(
      page,
      "document.querySelectorAll('.dv-wedit-handles .dv-wh').length > 0",
      label: 'drag.js to hang the resize handles',
      report: ctx.report,
    );
    final handles = await page
        .evaluate("document.querySelectorAll('.dv-wedit-handles .dv-wh').length");
    ctx.report.check('resize handles hang on the selection',
        handles is num && handles > 0, '$handles grips');
  }

  ctx.report.check('no page errors', page.pageErrors.isEmpty,
      page.pageErrors.join(' | '));

  await ctx.closePage(page);
}

/// Narrow an `evaluate` result to a map — same contract as the other studio
/// probes: an empty map fails every check with real values shown.
Map<String, dynamic> _map(dynamic value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};
