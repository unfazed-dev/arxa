// Capture the open fan at half radius for visual inspection.
import 'dart:io';
import 'package:appboxd/cdp.dart';
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
  await tab.evaluate('document.getElementById("arxa-dial-host").shadowRoot.querySelector("#dockbtn").click()');
  await Future.delayed(Duration(milliseconds: 800));
  final png = await tab.screenshot();
  File('/tmp/arxa_fan_open.png').writeAsBytesSync(png);
  stdout.writeln('saved /tmp/arxa_fan_open.png (${png.length} bytes)');
  await client.close();
}
