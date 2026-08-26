// Open-mode law probe: fan expanded => dial NEVER hides (cursor anywhere,
// any duration). Fan closed => the 30s backstop owns the tuck-away.
import 'dart:io';
import 'package:arxa/cdp.dart';
Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
Future<void> move(CdpSession t, int x, int y) async {
  await t.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': x, 'y': y});
}
Future<void> main() async {
  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture('http://127.0.0.1:4319/', settleMs: 2500);
  Future<String> vis() async => await js(tab,
      'document.getElementById("arxa-dial-host")?.style.visibility ?? "?"') as String;
  Future<void> tapFab() async => await js(tab,
      'document.getElementById("arxa-dial-host").shadowRoot.querySelector("#dockbtn").click()');

  // reveal
  for (var i = 0; i < 5; i++) {
    await move(tab, 1276 - i, 796 - i);
    await Future.delayed(Duration(milliseconds: 80));
  }
  await Future.delayed(Duration(milliseconds: 800));
  stdout.writeln('revealed: ${await vis()}');

  // OPEN THE FAN, then abandon the cursor mid-screen for 40s.
  await tapFab();
  await Future.delayed(Duration(milliseconds: 300));
  await move(tab, 640, 400);
  var everHidden = false;
  for (var s = 1; s <= 40; s++) {
    await Future.delayed(Duration(seconds: 1));
    if (s % 5 == 0) stdout.writeln('OPEN  ${s}s ${await vis()}');
    if (await vis() == 'hidden') { everHidden = true; stdout.writeln('FAIL: hid while open at ${s}s'); break; }
  }
  stdout.writeln(everHidden ? 'OPEN-MODE LAW: BROKEN' : 'OPEN-MODE LAW: HELD (never hid while fan open)');

  // CLOSE THE FAN -> the 30s timer starts from here.
  await tapFab();
  await Future.delayed(Duration(milliseconds: 300));
  final sw2 = Stopwatch()..start();
  var hiddenAt = -1;
  while (sw2.elapsed.inSeconds < 40) {
    await Future.delayed(Duration(milliseconds: 1000));
    if (await vis() == 'hidden') { hiddenAt = sw2.elapsed.inSeconds; break; }
  }
  stdout.writeln(hiddenAt < 0
      ? 'CLOSED: NEVER HID within 40s'
      : 'CLOSED: hid at ~${hiddenAt}s after close (backstop owns it)');
  stdout.writeln('console errors: ${tab.consoleErrors.length}');
  await client.close();
}
