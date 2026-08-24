// No-drag contract: a press-drag-release on the FAB must NOT move it, and
// the click toggle must still work afterwards.
import 'dart:io';
import 'package:appboxd/cdp.dart';
Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
Future<void> mouse(CdpSession t, String type, int x, int y, {Map<String, dynamic>? extra}) async {
  await t.send('Input.dispatchMouseEvent', {'type': type, 'x': x, 'y': y, ...?extra});
}
Future<String> rect(CdpSession tab) async => await js(tab,
    '(() => { const b = document.getElementById("arxa-dial-host").shadowRoot.querySelector("#dockbtn").getBoundingClientRect(); return b.x.toFixed(0) + "," + b.y.toFixed(0); })()') as String;
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
  final before = await rect(tab);
  stdout.writeln('before drag attempt: $before');
  await mouse(tab, 'mousePressed', 1228, 748, extra: {'button': 'left', 'buttons': 1, 'clickCount': 1});
  for (var i = 1; i <= 10; i++) {
    await mouse(tab, 'mouseMoved', 1228 - (72 * i ~/ 2), 748 - (44 * i ~/ 2), extra: {'buttons': 1});
    await Future.delayed(Duration(milliseconds: 40));
  }
  await mouse(tab, 'mouseReleased', 868, 528, extra: {'button': 'left'});
  await Future.delayed(Duration(milliseconds: 400));
  final after = await rect(tab);
  stdout.writeln('after  drag attempt: $after');
  final moved = before != after;
  stdout.writeln(moved ? 'FAIL: FAB MOVED' : 'PASS: FAB did not move');

  // the click toggle must still work
  await js(tab,
      'document.getElementById("arxa-dial-host").shadowRoot.querySelector("#dockbtn").click()');
  await Future.delayed(Duration(milliseconds: 250));
  final fanOpen = await js(tab,
      'document.getElementById("arxa-dial-host").shadowRoot.querySelector("#dock").classList.contains("open")');
  await js(tab,
      'document.getElementById("arxa-dial-host").shadowRoot.querySelector("#dockbtn").click()');
  await Future.delayed(Duration(milliseconds: 250));
  final fanClosed = await js(tab,
      'document.getElementById("arxa-dial-host").shadowRoot.querySelector("#dock").classList.contains("open")');
  stdout.writeln(!fanOpen && !fanClosed
      ? 'PASS: fan click-toggle still works'
      : 'FAIL: fan toggle broken (open=$fanOpen closedOpen=$fanClosed)');
  stdout.writeln('console errors: ${tab.consoleErrors.length}');
  await client.close();
}
