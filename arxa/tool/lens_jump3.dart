// Track-focus-jump probe: the tray slides live in a horizontal scroll-snap
// carousel; a clicked button takes focus and the browser may scroll the
// TRACK to reveal it -> the whole tray jumps horizontally. Measure
// track.scrollLeft / page scrollY / tray rect across picks of several cards.
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  final url = argv[0];
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 832);
    await tab.navigateAndSettle(url, settleMs: 3500);
    const sr = "document.querySelector('#arxa-dial-host').shadowRoot";
    await tab.evaluate("(() => { const r = $sr; r.querySelector('#dockbtn').click(); "
        "[...r.querySelectorAll('button')].filter(b => /Studio/.test(b.textContent))[0].click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 900));
    const probe = "(() => { const r = $sr; const track = r.querySelector('#track'); "
        "const tray = r.querySelector('#tray').getBoundingClientRect(); "
        "return { trackLeft: track.scrollLeft, pageY: Math.round(window.scrollY), "
        "trayTop: Math.round(tray.top), trayLeft: Math.round(tray.left) }; })()";
    stdout.writeln('baseline: ' + (await tab.evaluate(probe)).toString());
    final cards = await tab.evaluate("[...$sr.querySelectorAll('.palcard')].length");
    for (final idx in [0, 2, (cards as int) - 1]) {
      await tab.evaluate("(() => { const r = $sr; "
          "r.querySelectorAll('.palcard')[" + idx.toString() + "].click(); return 1; })()");
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final fast = await tab.evaluate(probe);
      await Future<void>.delayed(const Duration(milliseconds: 640));
      final settled = await tab.evaluate(probe);
      stdout.writeln('click card ' + idx.toString() + '  +60ms: ' + fast.toString());
      stdout.writeln('click card ' + idx.toString() + ' +700ms: ' + settled.toString());
    }
  } finally {
    await client.close();
  }
}
