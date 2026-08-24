// Round 3: track capture lifecycle on the button during a drag.
import 'dart:io';
import 'package:appboxd/cdp.dart';
Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
Future<void> mouse(CdpSession t, String type, int x, int y,
    {Map<String, dynamic>? extra}) async {
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
      window.__cap = { got: 0, lost: 0, hasAfterDown: '?', hasAfterMove: '?', pid: '?' };
      b.addEventListener('gotpointercapture', () => { window.__cap.got++; });
      b.addEventListener('lostpointercapture', () => { window.__cap.lost++; });
      b.addEventListener('pointerdown', () => {
        b.setPointerCapture(1);
      });
      addEventListener('pointermove', (ev) => {
        if (window.__cap.hasAfterMove === '?') {
          window.__cap.hasAfterMove = String(b.hasPointerCapture(1));
          window.__cap.pid = String(ev.pointerId);
        }
      });
    })()
  ''');
  await mouse(tab, 'mousePressed', 1228, 748,
      extra: {'button': 'left', 'buttons': 1, 'clickCount': 1});
  await Future.delayed(Duration(milliseconds: 100));
  stdout.writeln('after down : ' + await js(tab,
      '(() => { const b = document.getElementById("arxa-dial-host").shadowRoot.querySelector("#dockbtn"); window.__cap.hasAfterDown = String(b.hasPointerCapture(1)); return JSON.stringify(window.__cap); })()'));
  await mouse(tab, 'mouseMoved', 1108, 668, extra: {'buttons': 1});
  await Future.delayed(Duration(milliseconds: 150));
  await mouse(tab, 'mouseMoved', 1000, 600, extra: {'buttons': 1});
  await Future.delayed(Duration(milliseconds: 150));
  stdout.writeln('after moves: ' + await js(tab, 'JSON.stringify(window.__cap)'));
  await client.close();
}
