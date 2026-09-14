// Lens driver for the dial tray (operator, 2026-09-02 — Coolors-style
// palette grid evidence): open the Studio tray, screenshot; hover a stripe,
// screenshot again; report console/page errors like every lens verb.
// Usage: dart run tool/lens_tray.dart <url> <outPrefix> [width] [height] [settleMs]
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 2) {
    stderr.writeln(
        'usage: dart run tool/lens_tray.dart <url> <outPrefix> [w] [h] [settleMs]');
    exit(2);
  }
  final url = argv[0];
  final outPrefix = argv[1];
  final width = argv.length > 2 ? int.parse(argv[2]) : 1280;
  final height = argv.length > 3 ? int.parse(argv[3]) : 832;
  final settleMs = argv.length > 4 ? int.parse(argv[4]) : 3000;
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: settleMs);
    // Open the tray: dock button, then the Studio verb — all shadow-DOM.
    final opened = await tab.evaluate(
        "(() => { const sr = document.querySelector('#arxa-dial-host').shadowRoot; "
        "sr.querySelector('#dockbtn').click(); "
        "const v = [...sr.querySelectorAll('button')].filter(b => /Studio/.test(b.textContent)); "
        "if (!v.length) return 'no-verb'; v[0].click(); return 'ok'; })()");
    if (opened != 'ok') {
      stderr.writeln('lens tray: FAIL — could not open the tray: ' + opened.toString());
      exit(1);
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    File('$outPrefix.png').writeAsBytesSync(await tab.screenshot());
    // Hover the middle stripe of the second card — the hex label must show.
    final rect = await tab.evaluate(
        "(() => { const sr = document.querySelector('#arxa-dial-host').shadowRoot; "
        "const cards = [...sr.querySelectorAll('.palcard')]; "
        "if (cards.length < 2) return null; "
        "const st = cards[1].querySelectorAll('.palstripe')[2]; "
        "const r = st.getBoundingClientRect(); "
        "return { x: r.x + r.width / 2, y: r.y + r.height / 2, n: cards.length }; })()")
        as Map?;
    if (rect == null) {
      stderr.writeln('lens tray: FAIL — fewer than two palette cards');
      exit(1);
    }
    await tab.hover((rect['x'] as num).round(), (rect['y'] as num).round());
    await Future<void>.delayed(const Duration(milliseconds: 450));
    File('$outPrefix-hover.png').writeAsBytesSync(await tab.screenshot());
    stdout.writeln('lens tray: ' + url + ' -> ' + outPrefix + '{,-hover}.png ('
        + width.toString() + 'x' + height.toString() + ', cards='
        + rect['n'].toString() + ')');
    final errs = [...tab.consoleErrors, ...tab.pageErrors];
    if (errs.isNotEmpty) {
      stderr.writeln('lens tray: FAIL — console/page errors:');
      for (final e in errs) { stderr.writeln('  ' + e); }
      exit(1);
    }
  } finally {
    await client.close();
  }
}
