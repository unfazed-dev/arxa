import 'dart:async';
import 'package:appboxd/cdp.dart';

Future<void> main() async {
  final client = await CdpClient.launch();
  final s = await client.newTab();
  await s.enable();
  for (final r in [[390, 844], [744, 1133], [1280, 832]]) {
    await s.setViewport(r[0], r[1]);
    await s.navigate('http://127.0.0.1:4319/');
    await Future<void>.delayed(const Duration(seconds: 3));
    final m = await s.evaluate(r'''(() => {
      const d = document.documentElement, b = document.body;
      return JSON.stringify({
        innerW: window.innerWidth,
        clientW: d.clientWidth,
        scrollbarPx: window.innerWidth - d.clientWidth,
        docScrollH: d.scrollHeight,
        clientH: d.clientHeight,
        scrolls: d.scrollHeight > d.clientHeight,
        htmlOverflow: getComputedStyle(d).overflowY,
        bodyOverflow: getComputedStyle(b).overflowY,
        scrollbarWidthProp: getComputedStyle(d).scrollbarWidth,
      });
    })()''');
    print('${r[0]}x${r[1]} -> $m');
  }
  await client.close();
}
