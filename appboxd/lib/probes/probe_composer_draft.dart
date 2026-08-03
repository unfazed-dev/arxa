// probe-composer-draft — the hx-preserve pairing, in both shells that share the
// composer: a half-typed draft must SURVIVE an unrelated swap, and must be
// CLEARED by a send. Preserving on send would leave the sent text sitting there
// ready to be sent twice, so these two assertions only mean anything together.
//
// Dart port of `archives/tooling-pre-dart/tools/studio-probes/probe-composer-draft.mjs` (4 checks, 2 sections). The
// reference port for the harness: the smallest real probe, ported verbatim so
// its output diffs textually against the original during the parity window.

import 'dart:convert';

import 'package:appboxd/cdp.dart';
import 'package:appboxd/probes/probe_base.dart';

const String _textarea = 'textarea[name="text"]';

/// The pin control that triggers an unrelated swap. Two selectors because the
/// two shells expose different affordances; either one is a swap the composer
/// did not ask for, which is the whole point of check 1.
const String _pin =
    '.dv-tile .dv-tile-tools a[hx-get*="context"], .cs-thumb';

const Probe composerDraftProbe = Probe(
  name: 'composer-draft',
  summary: 'hx-preserve: a draft survives an unrelated swap, and a send clears it',
  // Check 2 submits the composer, which POSTs a real message into the served
  // project. The .mjs original never guarded this — see docs/probes-capability-map.md.
  mutates: true,
  body: _run,
);

Future<void> _run(ProbeContext ctx) async {
  for (final shell in ['/design', '/design/freeze']) {
    final page = await ctx.newPage();
    await ctx.goto(page, shell);
    ctx.report.section(shell);

    // 1. an unrelated interaction must NOT eat the draft
    await _fill(page, shell, 'HALF TYPED DRAFT');
    final hasPin = await page.evaluate(
        'document.querySelector(${jsonEncode(_pin)}) !== null');
    if (hasPin == true) {
      // Synthetic: the tile tool rail is hover-revealed, so a real pointer
      // cannot reach it in a headless run. The page listens for the click
      // event, which is what this dispatches.
      await page.clickSelector(_pin, synthetic: true);
      await waitQuiet(page, report: ctx.report);
      final value = await page.evaluate(
          'document.querySelector(${jsonEncode(_textarea)}).value');
      ctx.report.check(
          'draft survives an unrelated swap', value == 'HALF TYPED DRAFT');
    } else {
      ctx.report.skip('no pin control on this shell');
    }

    // 2. sending must clear it
    await _fill(page, shell, 'MESSAGE TO SEND');
    await page.evaluate("(() => { const f = document.querySelector('#composer');"
        ' f.requestSubmit ? f.requestSubmit() : f.submit(); return true; })()');
    // The post-condition IS the assertion here (the textarea clears), so name
    // it rather than settling: an empty value is unambiguous.
    await probeWaitFor(
      page,
      '(() => { const t = document.querySelector(${jsonEncode(_textarea)});'
          " return !t || t.value === ''; })()",
      label: 'the composer textarea to clear',
      report: ctx.report,
    );
    final after = await page.evaluate(
        '(() => { const t = document.querySelector(${jsonEncode(_textarea)});'
        " return t ? t.value : '(gone)'; })()");
    final value = after is String ? after : '(gone)';
    ctx.report
        .check('textarea clears after send', value == '', jsonEncode(value));

    await ctx.closePage(page);
  }
}

/// Type into the composer, or stop the run.
///
/// [CdpSession.fillSelector] reports a missing element by returning false, and
/// swallowing that here would let both checks run against a page with no
/// composer at all: check 1 would compare null to the draft and report the
/// feature broken, when the truth is that the probe never found the thing it
/// was testing. The `.mjs` original gets this for free — Playwright's `fill`
/// throws when the locator never resolves — so raising here keeps the failure
/// symptom the same shape (`ERR …`, run aborted, non-zero exit) as well as the
/// count.
Future<void> _fill(CdpSession page, String shell, String value) async {
  if (!await page.fillSelector(_textarea, value)) {
    throw StateError('no composer textarea ($_textarea) on $shell —'
        ' the shell never rendered one, so neither check below can mean anything');
  }
}
