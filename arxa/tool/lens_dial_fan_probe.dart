// Fan probe: (a) geometry - verb centers at ~95px from dock center
// (half the old 190); (b) stagger - visible-verb count climbs gradually
// after the open click instead of 0->8 in one step; (c) collapse is
// immediate-ish (no reverse stagger).
import 'dart:io';
import 'package:arxa/cdp.dart';
Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
Future<void> mouse(CdpSession t, int x, int y) async {
  await t.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': x, 'y': y});
}
Future<void> main() async {
  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture('http://127.0.0.1:4319/', settleMs: 2500);
  for (var i = 0; i < 5; i++) {
    await mouse(tab, 1276 - i, 796 - i);
    await Future.delayed(Duration(milliseconds: 80));
  }
  await Future.delayed(Duration(milliseconds: 900));

  // geometry
  final dist = await js(tab, '''
    (() => {
      const sr = document.getElementById('arxa-dial-host').shadowRoot;
      const d = sr.querySelector('#dock').getBoundingClientRect();
      const v = sr.querySelector('.verb').getBoundingClientRect();
      const dx = (v.x + v.width / 2) - (d.x + d.width / 2);
      const dy = (v.y + v.height / 2) - (d.y + d.height / 2);
      return Math.round(Math.hypot(dx, dy));
    })()
  ''');
  stdout.writeln('verb radius: $dist px (target ~95)');
  stdout.writeln((dist as num).abs() >= 85 && (dist).abs() <= 105
      ? 'PASS radius halved' : 'FAIL radius off');

  // stagger timeline
  await js(tab,
      'document.getElementById("arxa-dial-host").shadowRoot.querySelector("#dockbtn").click()');
  final samples = <int>[];
  final t0 = Stopwatch()..start();
  while (t0.elapsedMilliseconds < 700) {
    final c = await js(tab, '''
      (() => {
        const vs = document.getElementById('arxa-dial-host')
          .shadowRoot.querySelectorAll('.verb');
        let k = 0; vs.forEach(v => { if (parseFloat(getComputedStyle(v).opacity) > 0.5) k++; });
        return k;
      })()
    ''');
    samples.add((c as num).toInt());
    await Future.delayed(Duration(milliseconds: 35));
  }
  stdout.writeln('visible-count timeline: $samples');
  final distinct = samples.toSet().length;
  final grew = samples.any((v) => v >= 2) && samples.first < 8;
  stdout.writeln(distinct >= 4 && grew
      ? 'PASS stagger (gradual climb, $distinct distinct levels)'
      : 'FAIL stagger (all-at-once? levels=$distinct)');

  // collapse: after close click, everything should vanish together fast
  await js(tab,
      'document.getElementById("arxa-dial-host").shadowRoot.querySelector("#dockbtn").click()');
  await Future.delayed(Duration(milliseconds: 400));
  final closed = await js(tab, '''
    (() => {
      const vs = document.getElementById('arxa-dial-host')
        .shadowRoot.querySelectorAll('.verb');
      let k = 0; vs.forEach(v => { if (parseFloat(getComputedStyle(v).opacity) > 0.05) k++; });
      return k;
    })()
  ''');
  stdout.writeln('after close: $closed still visible (expect 0)');
  stdout.writeln('console errors: ${tab.consoleErrors.length}');
  await client.close();
}
