// Precise jump reproduction (operator, 2026-09-09): scroll the slide DOWN,
// pick a card, track scrollTop across the following frames + burst shots.
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  final url = argv[0];
  final outPrefix = argv[1];
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(390, 844);
    await tab.navigateAndSettle(url, settleMs: 3500);
    const sr = "document.querySelector('#arxa-dial-host').shadowRoot";
    await tab.evaluate("(() => { const r = $sr; r.querySelector('#dockbtn').click(); "
        "[...r.querySelectorAll('button')].filter(b => /Studio/.test(b.textContent))[0].click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 900));
    // scroll the slide to its bottom and confirm
    final s0 = await tab.evaluate("(() => { const r = $sr; const s = r.querySelector('.slide'); "
        "s.scrollTop = s.scrollHeight; return s.scrollTop; })()");
    stdout.writeln('scrolled to: ' + s0.toString());
    File('$outPrefix-scrolled.png').writeAsBytesSync(await tab.screenshot());
    // instrument scrollTop mutations, then click the LAST card
    await tab.evaluate("(() => { const r = $sr; const s = r.querySelector('.slide'); "
        "window.__jump = [{ t: 0, st: s.scrollTop }]; "
        "const rec = () => { window.__jump.push({ t: Math.round(performance.now()), st: s.scrollTop }); }; "
        "s.addEventListener('scroll', rec, { passive: true }); "
        "const cards = [...r.querySelectorAll('.palcard')]; "
        "cards[cards.length - 1].click(); "
        "window.__jump.push({ t: Math.round(performance.now()), st: s.scrollTop, note: 'sync-after-click' }); "
        "return 1; })()");
    for (final ms in [40, 120, 300, 700]) {
      await Future<void>.delayed(Duration(milliseconds: ms));
      final st = await tab.evaluate("$sr.querySelector('.slide').scrollTop");
      stdout.writeln('+' + ms.toString() + 'ms scrollTop=' + st.toString());
    }
    File('$outPrefix-after.png').writeAsBytesSync(await tab.screenshot());
    final log = await tab.evaluate("JSON.stringify(window.__jump)");
    stdout.writeln('scroll events: ' + log.toString());
  } finally {
    await client.close();
  }
}
