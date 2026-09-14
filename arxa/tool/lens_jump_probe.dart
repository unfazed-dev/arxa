// Measure the tray jump on palette pick (operator, 2026-09-09): geometry +
// scroll before/after a card click, plus paired screenshots.
// Usage: dart run tool/lens_jump_probe.dart <url> <outPrefix> [w h]
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  final url = argv[0];
  final outPrefix = argv[1];
  final width = argv.length > 2 ? int.parse(argv[2]) : 1280;
  final height = argv.length > 3 ? int.parse(argv[3]) : 832;
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: 3500);
    const sr = "document.querySelector('#arxa-dial-host').shadowRoot";
    await tab.evaluate("(() => { const r = $sr; r.querySelector('#dockbtn').click(); "
        "[...r.querySelectorAll('button')].filter(b => /Studio/.test(b.textContent))[0].click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 900));
    // scroll the slide to the bottom so a scroll reset is observable
    const probe = "(() => { const r = $sr; const slide = r.querySelector('.slide'); "
        "const cards = [...r.querySelectorAll('.palcard')]; "
        "const grid = r.querySelector('.palgrid'); "
        "const g = grid.getBoundingClientRect(); "
        "return { scrollTop: slide.scrollTop, scrollH: slide.scrollHeight, "
        "clientH: slide.clientHeight, gridTop: g.top, gridH: g.height, "
        "cardTops: cards.map(c => Math.round(c.getBoundingClientRect().top)) }; })()";
    final before = await tab.evaluate(probe);
    File('$outPrefix-before.png').writeAsBytesSync(await tab.screenshot());
    // pick the LAST card (Forest Neon region — forces the biggest state change)
    await tab.evaluate("(() => { const r = $sr; const cards = [...r.querySelectorAll('.palcard')]; "
        "cards[cards.length - 2].click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final after = await tab.evaluate(probe);
    File('$outPrefix-after.png').writeAsBytesSync(await tab.screenshot());
    stdout.writeln('BEFORE ' + before.toString());
    stdout.writeln('AFTER  ' + after.toString());
    final errs = [...tab.consoleErrors, ...tab.pageErrors];
    if (errs.isNotEmpty) { stdout.writeln('console errors: ' + errs.join(' | ')); }
  } finally {
    await client.close();
  }
}
