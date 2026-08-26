// Precision pass: reveal once, cursor away, poll every 1s - print the exact
// second the backstop tucks the dial away.
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
  for (var i = 0; i < 5; i++) {
    await move(tab, 1276 - i, 796 - i);
    await Future.delayed(Duration(milliseconds: 80));
  }
  await Future.delayed(Duration(milliseconds: 800));
  stdout.writeln('revealed: ${await vis()}');
  await move(tab, 640, 400);
  final sw = Stopwatch()..start();
  var reported = false;
  while (sw.elapsed.inSeconds < 45) {
    await Future.delayed(Duration(milliseconds: 1000));
    final v = await vis();
    stdout.writeln('${sw.elapsed.inSeconds}s $v');
    if (v == 'hidden') { stdout.writeln('HIDDEN AT ~${sw.elapsed.inSeconds}s'); reported = true; break; }
  }
  if (!reported) stdout.writeln('NEVER HIDDEN within 45s');
  stdout.writeln('console errors: ${tab.consoleErrors.length}');
  await client.close();
}
