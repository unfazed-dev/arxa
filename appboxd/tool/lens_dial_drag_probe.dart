// Drag probe: press the FAB, drag it toward mid-left, release - report the
// button rect before/after and where the code THOUGHT it placed the dock.
import 'dart:convert';
import 'dart:io';
import 'package:appboxd/cdp.dart';
Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
Future<void> mouse(CdpSession t, String type, int x, int y, {Map<String, dynamic>? extra}) async {
  await t.send('Input.dispatchMouseEvent', {
    'type': type, 'x': x, 'y': y, ...?extra,
  });
}
Future<void> main() async {
  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture('http://127.0.0.1:4319/', settleMs: 2500);
  Future<Map<String, dynamic>> rect() async {
    final r = await js(tab, '''
      (() => {
        const sr = document.getElementById('arxa-dial-host').shadowRoot;
        const b = sr.querySelector('#dockbtn').getBoundingClientRect();
        const d = sr.querySelector('#dock');
        return JSON.stringify({ x: b.x, y: b.y, w: b.width, h: b.height,
          left: d.style.left || '(css)', right: d.style.right || '(css)',
          top: d.style.top || '(css)', pos: getComputedStyle(d).position });
      })()
    ''');
    return r is String ? Map<String, dynamic>.from(jsonDecode(r)) : {};
  }
  Future<void> reveal() async {
    for (var i = 0; i < 5; i++) {
      await mouse(tab, 'mouseMoved', 1276 - i, 796 - i);
      await Future.delayed(Duration(milliseconds: 80));
    }
    await Future.delayed(Duration(milliseconds: 900));
  }
  await reveal();
  final before = await rect();
  stdout.writeln('before: $before');
  // drag FAB from its center to (500, 300)
  final cx = ((before['x'] as num) + (before['w'] as num) / 2).round();
  final cy = ((before['y'] as num) + (before['h'] as num) / 2).round();
  await mouse(tab, 'mousePressed', cx, cy, extra: {'button': 'left', 'buttons': 1, 'clickCount': 1});
  for (var i = 1; i <= 10; i++) {
    await mouse(tab, 'mouseMoved',
        cx + ((500 - cx) * i ~/ 10), cy + ((300 - cy) * i ~/ 10),
        extra: {'buttons': 1});
    await Future.delayed(Duration(milliseconds: 40));
  }
  await mouse(tab, 'mouseReleased', 500, 300, extra: {'button': 'left', 'clickCount': 1});
  await Future.delayed(Duration(milliseconds: 400));
  final after = await rect();
  stdout.writeln('after:  $after');
  final dx = ((after['x'] as num) - (before['x'] as num)).abs();
  stdout.writeln('moved by x: ${dx.toStringAsFixed(1)}px -> ${dx > 200 ? "DRAG OK" : "DRAG BROKEN"}');
  stdout.writeln('console errors: ${tab.consoleErrors.length}');
  await client.close();
}
