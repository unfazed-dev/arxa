// Element-level diff: which tray descendant grows during the pick transient.
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  final url = argv[0];
  final outPrefix = argv[1];
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
    const probe = "(() => { const r = $sr; const out = {}; "
        "const kids = r.querySelectorAll('#tray, #track, .slide, .slidebody, .palgrid, .sect, .facet, .btnrow, .ctl, .pvnote'); "
        "kids.forEach((k, i) => { const key = (k.id || k.className) + '#' + i; "
        "out[key] = Math.round(k.getBoundingClientRect().height); }); "
        "return out; })()";
    final before = (await tab.evaluate(probe)) as Map;
    await tab.evaluate("$sr.querySelectorAll('.palcard')[2].click()");
    await Future<void>.delayed(const Duration(milliseconds: 60));
    File('$outPrefix-mid.png').writeAsBytesSync(await tab.screenshot());
    final mid = (await tab.evaluate(probe)) as Map;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final after = (await tab.evaluate(probe)) as Map;
    final keys = <String>{...before.keys.map((k) => k.toString()), ...mid.keys.map((k) => k.toString())};
    for (final k in keys) {
      final b = before[k], m = mid[k], a = after[k];
      if (b != m || m != a) {
        stdout.writeln('CHANGED ' + k + ': rest=' + b.toString() + ' mid=' + m.toString() + ' after=' + a.toString());
      }
    }
    stdout.writeln('--- keys only in mid: ' + mid.keys.where((k) => !before.containsKey(k)).toList().toString());
  } finally {
    await client.close();
  }
}
