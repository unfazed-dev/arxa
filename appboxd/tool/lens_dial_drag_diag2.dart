// Round 2: does ANY window-level pointermove arrive after press? And does
// the drag work when setPointerCapture is stubbed out?
import 'dart:io';
import 'package:appboxd/cdp.dart';
Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
Future<void> mouse(CdpSession t, String type, int x, int y, {Map<String, dynamic>? extra}) async {
  await t.send('Input.dispatchMouseEvent', {'type': type, 'x': x, 'y': y, ...?extra});
}
Future<void> main() async {
  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture('http://127.0.0.1:4319/', settleMs: 2500);
  for (var i = 0; i < 5; i++) {
    await mouse(tab, 'mouseMoved', 1276 - i, 796 - i);
    await Future.delayed(Duration(milliseconds: 80));
  }
  await Future.delayed(Duration(milliseconds: 900));
  await js(tab, '''
    (() => {
      const sr = document.getElementById('arxa-dial-host').shadowRoot;
      const b = sr.querySelector('#dockbtn');
      b.setPointerCapture = () => {};   // STUB the capture
      window.__win = 0; window.__btn = 0;
      addEventListener('pointermove', () => { window.__win++; });
      b.addEventListener('pointermove', () => { window.__btn++; });
    })()
  ''');
  await mouse(tab, 'mousePressed', 1228, 748, extra: {'button': 'left', 'buttons': 1, 'clickCount': 1});
  for (var i = 1; i <= 6; i++) {
    await mouse(tab, 'mouseMoved', 1228 - i * 60, 748 - i * 30, extra: {'buttons': 1});
    await Future.delayed(Duration(milliseconds: 50));
  }
  await mouse(tab, 'mouseReleased', 868, 568, extra: {'button': 'left'});
  await Future.delayed(Duration(milliseconds: 250));
  stdout.writeln('window moves: ${await js(tab, 'String(window.__win)')}');
  stdout.writeln('button moves: ${await js(tab, 'String(window.__btn)')}');
  stdout.writeln('dock left/top: ${await js(tab,
      '(() => { const d = document.getElementById("arxa-dial-host").shadowRoot.querySelector("#dock"); return d.style.left + " | " + d.style.top; })()')}');
  final r = await js(tab,
      '(() => { const b = document.getElementById("arxa-dial-host").shadowRoot.querySelector("#dockbtn").getBoundingClientRect(); return b.x.toFixed(0) + "," + b.y.toFixed(0); })()');
  stdout.writeln('fab rect now: $r');
  await client.close();
}
