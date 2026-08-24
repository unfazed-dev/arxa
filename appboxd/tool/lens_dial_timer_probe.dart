// One-off lens probe: drive the dial hot-corner + 30s auto-hide in a real
// browser and report OBSERVED behavior (not source assertions).
//   dart run tool/lens_dial_timer_probe.dart
import 'dart:io';

import 'package:appboxd/cdp.dart';

Future<dynamic> js(CdpSession tab, String expr) => tab.evaluate(expr);

Future<void> move(CdpSession tab, int x, int y) async {
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mouseMoved', 'x': x, 'y': y});
}

Future<void> main() async {
  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture('http://127.0.0.1:4319/',
      settleMs: 2500);

  String pose(String label) => '';
  Future<String> vis() async => await js(
          tab, 'document.getElementById("arxa-dial-host")?.style.visibility ?? "NO-HOST"')
      as String;

  // baseline: parked
  stdout.writeln('t=0        visibility=${await vis()}');

  // hover into the 50px corner (1280x800 -> corner zone x>=1230,y>=750)
  for (var i = 0; i < 5; i++) {
    await move(tab, 1276 - i, 796 - i);
    await Future.delayed(Duration(milliseconds: 80));
  }
  await Future.delayed(Duration(milliseconds: 1200));
  stdout.writeln('t~+1.5s    visibility=${await vis()}  (after corner hover)');

  // branch A - cursor LEAVES: current code should hide instantly, which
  // would make the 30s timer unreachable on this path.
  await move(tab, 640, 400);
  await Future.delayed(Duration(milliseconds: 800));
  stdout.writeln('t~+2.5s    visibility=${await vis()}  (after leaving)');

  // branch B - cursor HOLDS inside the corner past 30s: moves every second.
  for (var i = 0; i < 5; i++) {
    await move(tab, 1276, 796);
    await Future.delayed(Duration(milliseconds: 120));
  }
  for (var s = 5; s <= 35; s += 5) {
    await Future.delayed(Duration(seconds: 5));
    if (s % 10 == 0 || s == 5) {
      for (var i = 0; i < 3; i++) {
        await move(tab, 1276 + (i % 2), 796 - (i % 2));
        await Future.delayed(Duration(milliseconds: 60));
      }
    }
    stdout.writeln('t~+${s}s     visibility=${await vis()}');
  }

  // branch C (THE contract): fresh reveal, cursor leaves, WAIT for the
  // 30s backstop - visibility must return to hidden at ~30s, not before.
  for (var i = 0; i < 5; i++) {
    await move(tab, 1276 - i, 796 - i);
    await Future.delayed(Duration(milliseconds: 80));
  }
  await Future.delayed(Duration(milliseconds: 600));
  stdout.writeln('C t~+1s     visibility=${await vis()}  (re-revealed)');
  await move(tab, 640, 400);
  for (var s = 5; s <= 35; s += 5) {
    await Future.delayed(Duration(seconds: 5));
    stdout.writeln('C t~+${s}s     visibility=${await vis()}${s >= 30 ? (await vis()) == 'hidden' ? '  <-- TIMER WORKS' : '  <-- TIMER STILL BROKEN' : ''}');
  }

  final errors = tab.consoleErrors;
  stdout.writeln('console errors: ${errors.length}');
  for (final e in errors.take(5)) {
    stdout.writeln('  ERR: $e');
  }
  await client.close();
}
