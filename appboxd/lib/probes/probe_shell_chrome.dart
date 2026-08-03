// probe_shell_chrome.dart — the viewer's two shell panels SURVIVE every swap.
// Ported from `tools/probe-shell-chrome.mjs`.
//
// The regression this locks down: #viewerSwap rendered `dv.designViewer(c.viewer)`
// with no second arg while the full page rendered it WITH a chrome object, and
// design_viewer.html guards the whole <header class="dv-topbar"> behind
// `{% if chrome %}`. Every control that swaps #design-viewer — the lens chips
// (.dv-chip), the device rungs (.mini-panel-tab) and the bg swatches
// (.mini-swatch) — therefore went through the ONE render path with no chrome
// and deleted the top section, permanently, until a full page reload. The
// bottom section is unguarded so the bar itself stayed, which is what made the
// loss easy to miss: the viewer still looked furnished.
//
// Why probe-explode section D never saw it: section D opens with a FRESH
// full-page navigation to /design and only then reads .dv-topbar. A full page
// render is the one state where chrome is guaranteed present, so section D
// samples the only passing case and never exercises a fragment swap at all.
// This probe asserts the panels AFTER each swap, which is the state the user
// is actually in.
import 'dart:convert';

import 'package:appboxd/cdp.dart';
import 'package:appboxd/probes/probe_base.dart';

/// Section F clicks a live flow-move control and then undoes it, so this
/// writes into whatever project the server is bound to. The harness runs the
/// disposable-project guard off this declaration.
const Probe shellChromeProbe = Probe(
  name: 'shell-chrome',
  summary: "the viewer's shell panels survive every swap that re-renders it",
  mutates: true,
  body: _run,
);

/// Marks the element a section is about to click.
///
/// Every control below is chosen by INDEX, never by href: `withParams` elides
/// defaults (mobile drops `vp=`, views drops `mode=`) and echoes whatever else
/// is live, so an href matcher would miss. [CdpSession.clickSelector] takes a
/// selector rather than an index, so the index is resolved in the page and the
/// winner is tagged with an attribute the selector can then name.
const String _nthAttr = 'data-probe-nth';

/// Same idea for section F's move tool, kept separate so tagging the tool
/// cannot clear the tag on a rung the caller is still holding.
const String _moveAttr = 'data-probe-move';

/// The one hover-revealed control in this probe. `:not([disabled])` matters —
/// tile 1's move-earlier renders disabled, and clicking it would push nothing
/// onto the undo stack and fail the undo-enabled check spuriously.
const String _moveToolSel = '.dv-tool[hx-post*="/move/"]:not([disabled])';

const String _undoSel = '.dv-shell-act[hx-post="/design/undo/canvas"]';
const String _redoSel = '.dv-shell-act[hx-post="/design/redo/canvas"]';

/// The panel census, read from inside `.panel-viewer` (the fullscreen target).
const String _censusJs = r'''
(() => {
  const v = document.querySelector('.panel-viewer');
  if (!v) return null;
  const inside = (s) => !!v.querySelector(s);
  return {
    topbar: inside('.dv-topbar'),
    title: inside('.dv-topbar-title'),
    botbar: inside('.dv-botbar'),
    miniDocked: inside('.dv-botbar .mini-panel'),
    acts: [...v.querySelectorAll('.dv-shell-act')].map((a) => ({
      tag: a.tagName,
      disabled: a.disabled === true,
      label: a.getAttribute('aria-label'),
      post: a.getAttribute('hx-post'),
    })),
    danger: v.querySelectorAll('.is-danger').length,
  };
})()
''';

Future<void> _run(ProbeContext ctx) async {
  final report = ctx.report;
  final page = await ctx.newPage(width: 1800, height: 1100);
  try {
    await ctx.goto(page, '/design');
    await probeWaitFor(
      page,
      "(() => { const v = document.querySelector('.panel-viewer');"
      " return !!v && !!v.querySelector('.dv-shell-act'); })()",
      timeout: const Duration(seconds: 15),
      label: 'the viewer shell + its chrome actions',
      report: report,
    );

    report.section('A. first load');
    _panelsOk(report, 'first load', await _census(page));

    report.section(
        'B. viewport rungs (.mini-panel-tab) — each one used to delete the top panel');
    for (final rung in const [(1, 'tablet'), (2, 'desktop'), (0, 'mobile')]) {
      await _swapNth(ctx, page, '.mini-panel-tab', rung.$1, 'rung ${rung.$2}');
      _panelsOk(report, 'rung ${rung.$2}', await _census(page));
    }

    report.section('C. bg swatches (.mini-swatch) — same swap target, same defect');
    for (final bg in const ['warm', 'slate', 'canvas']) {
      await _swap(ctx, page, '.mini-swatch-$bg', 'bg $bg');
      _panelsOk(report, 'bg $bg', await _census(page));
    }

    report.section('D. lens switches (.dv-chip) — views / flows / proto');
    for (final lens in const [(1, 'flows'), (2, 'proto'), (0, 'views')]) {
      await _swapNth(ctx, page, '.dv-chip', lens.$1, 'lens ${lens.$2}');
      _panelsOk(report, 'lens ${lens.$2}', await _census(page));
    }

    report.section('E. chrome.actions is exactly canvas undo + redo');
    final acts = _acts(await _census(page));
    report.check('exactly two shell actions', acts.length == 2, '${acts.length}');
    report.check('both are buttons (mutations, not links)',
        acts.every((a) => a['tag'] == 'BUTTON'),
        acts.map((a) => a['tag']).join(','));
    report.check('action 1 POSTs canvas undo',
        _at(acts, 0)?['post'] == '/design/undo/canvas', '${_at(acts, 0)?['post']}');
    report.check('action 2 POSTs canvas redo',
        _at(acts, 1)?['post'] == '/design/redo/canvas', '${_at(acts, 1)?['post']}');
    // A fresh session has stepped nothing, so BOTH ends of the stack are empty.
    report.check('undo disabled at the bottom of the stack',
        _at(acts, 0)?['disabled'] == true);
    report.check('redo disabled at the top of the stack',
        _at(acts, 1)?['disabled'] == true);

    report.section('F. a canvas mutation arms undo, and undoing re-arms redo');
    await _armAndStepBack(ctx, page);

    report.check('no page errors', page.pageErrors.isEmpty,
        page.pageErrors.join(' | '));
  } finally {
    await ctx.closePage(page);
  }
}

/// Section F. A flow nudge is the cheapest canvas entry: it pushes onto
/// `undoStacks.canvas`.
Future<void> _armAndStepBack(ProbeContext ctx, CdpSession page) async {
  final report = ctx.report;
  await _swapNth(ctx, page, '.dv-chip', 1, 'lens flows');

  // Tag the move tool and learn which tile hosts it, in one read: the tool is
  // hover-revealed, and the tile is what has to be hovered to reveal it.
  final tileId = await page.evaluate(
    '(() => {'
    ' document.querySelectorAll("[$_moveAttr]")'
    '   .forEach((e) => e.removeAttribute("$_moveAttr"));'
    ' const el = document.querySelector(${jsonEncode(_moveToolSel)});'
    ' if (!el) return null;'
    ' el.setAttribute("$_moveAttr", "1");'
    ' return el.closest(".dv-tile")?.dataset.id ?? ""; })()',
  );
  if (tileId is! String) {
    report.check('found a flow move button to arm the stack', false,
        'no $_moveToolSel on the flows lens');
    return;
  }

  // The tool is CSS hover-revealed (.dv-tile-chrome sits above it until
  // :hover / :focus-within). A real hover on the always-visible tile opens the
  // gate first, then the click exercises the real reveal. clickSelector's own
  // hover-then-click would very likely suffice — it re-measures after hovering
  // for exactly this class of reveal — but hovering the TILE is what the
  // original asserted, and a synthetic click would bypass the reveal entirely
  // and keep passing even if the reveal itself broke (task #49).
  if (tileId.isNotEmpty) {
    await page.hoverSelector('.dv-tile[data-id="$tileId"]');
  }
  final nudged = await page.clickSelector('[$_moveAttr="1"]');
  if (!nudged) {
    report.check('clicked the flow move button', false,
        'the tool was tagged but no pointer could reach it');
    return;
  }

  // flowMove and undo/redo are async (facade.undo awaits a file write) and
  // #panelsSwap re-renders the whole stage, so a fixed wait-then-read races
  // that write under load (task #48/#50 root cause: a flake, not session
  // contamination). Poll the condition each check exists to prove.
  //
  // probeWaitFor warns and returns false rather than throwing. That contract is
  // load-bearing here: a bare throw used to abort the run from inside the try,
  // silently deleting the eight checks below while still reporting "1 FAILED"
  // with no indication that eight assertions never executed. That is how a real
  // defect hid. A probe must report what it found, not stop at the first
  // surprise.
  await probeWaitFor(
    page,
    "document.querySelector('.panel-viewer $_undoSel')?.disabled === false",
    timeout: const Duration(seconds: 5),
    label: 'undo to become enabled after a flow move',
    report: report,
  );
  final armed = await _census(page);
  _panelsOk(report, 'after a flow move', armed);
  final armedActs = _acts(armed);
  report.check('undo enabled once the canvas stack is non-empty',
      _at(armedActs, 0)?['disabled'] == false);
  report.check('redo still disabled (nothing stepped back yet)',
      _at(armedActs, 1)?['disabled'] == true);

  await page.clickSelector(_undoSel);
  // THIS is the one that fails under concurrent load (task #55): redo stays
  // disabled well past 5s, and past 20s in an independent run. Reported as a
  // failed check, not as an aborted run — the difference decides whether the
  // next reader sees a product defect or a broken probe. The 5s is part of what
  // the check documents; do not raise it to make a red go green.
  await probeWaitFor(
    page,
    "document.querySelector('.panel-viewer $_redoSel')?.disabled === false",
    timeout: const Duration(seconds: 5),
    label: 'redo to re-enable after undo',
    report: report,
  );
  final stepped = await _census(page);
  _panelsOk(report, 'after undo', stepped);
  report.check('redo enabled after stepping back',
      _at(_acts(stepped), 1)?['disabled'] == false);
}

/// The five-check shape asserted in every state above, so it lives here once.
///
/// The foot line (.dv-botbar-foot) that used to be asserted here is GONE by
/// request — removed from design_viewer.html in 5bb8850 along with the chat
/// context note. It was a genuine chrome-loss signal when it existed; the top
/// panel checks now carry that job alone. Deleting the assertion rather than
/// relaxing it: an element that no longer exists cannot regress, and a check
/// that can only fail is noise that trains you to ignore reds.
void _panelsOk(ProbeReport report, String label, Map<String, dynamic>? s) {
  report.check('$label: top panel present', s?['topbar'] == true);
  report.check('$label: title present', s?['title'] == true);
  report.check('$label: bottom panel present', s?['botbar'] == true);
  report.check('$label: mini panel docked in the bottom panel',
      s?['miniDocked'] == true);
  report.check('$label: zero is-danger nodes', s?['danger'] == 0,
      s == null ? 'no viewer' : '${s['danger']}');
}

Future<Map<String, dynamic>?> _census(CdpSession page) async {
  final raw = await page.evaluate(_censusJs);
  return raw is Map ? raw.cast<String, dynamic>() : null;
}

List<Map<String, dynamic>> _acts(Map<String, dynamic>? census) {
  final raw = census?['acts'];
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}

Map<String, dynamic>? _at(List<Map<String, dynamic>> acts, int i) =>
    i < acts.length ? acts[i] : null;

/// htmx's own afterSettle counter, installed by [trackTransitions].
///
/// The old fixed 1200ms guessed how long a swap takes; the DOM offers no honest
/// post-condition (the stage and .panel-viewer are present both before and
/// after, so any check on them is satisfied instantly and waits for nothing).
Future<int> _settleCount(CdpSession page) async {
  final n = await page.evaluate('(window.__hxSettled || 0)');
  return n is num ? n.toInt() : 0;
}

Future<void> _awaitSwap(
    ProbeContext ctx, CdpSession page, int before, String what) async {
  await probeWaitFor(
    page,
    '(window.__hxSettled || 0) > $before',
    timeout: const Duration(seconds: 8),
    label: 'htmx to settle the panel swap ($what)',
    report: ctx.report,
  );
}

/// Click the [index]th match of [selector] and wait for the swap it causes.
///
/// The original threw when the index was absent, which sent the whole run into
/// its catch and reported one error in place of every remaining assertion. This
/// reports the missing control as a failed check and carries on, matching the
/// harness contract that section F's comment makes load-bearing.
Future<void> _swapNth(ProbeContext ctx, CdpSession page, String selector,
    int index, String what) async {
  final tagged = await page.evaluate(
    '(() => {'
    ' document.querySelectorAll("[$_nthAttr]")'
    '   .forEach((e) => e.removeAttribute("$_nthAttr"));'
    ' const els = document.querySelectorAll(${jsonEncode(selector)});'
    ' if (!els[$index]) return els.length;'
    ' els[$index].setAttribute("$_nthAttr", "1");'
    ' return -1; })()',
  );
  if (tagged is! num || tagged != -1) {
    ctx.report.check('found $selector[$index] to click ($what)', false,
        'found ${tagged is num ? tagged.toInt() : 0}');
    return;
  }
  await _clickAndSettle(ctx, page, '[$_nthAttr="1"]', what);
}

Future<void> _swap(
    ProbeContext ctx, CdpSession page, String selector, String what) async {
  await _clickAndSettle(ctx, page, selector, what);
}

Future<void> _clickAndSettle(
    ProbeContext ctx, CdpSession page, String selector, String what) async {
  final before = await _settleCount(page);
  final clicked = await page.clickSelector(selector);
  if (!clicked) {
    ctx.report.check('clicked $what', false, 'no element matched $selector');
    return;
  }
  await _awaitSwap(ctx, page, before, what);
}
