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
      const over = [...document.querySelectorAll('*')]
        .filter(e => e.getBoundingClientRect().right > d.clientWidth + 1)
        .slice(0, 4)
        .map(e => e.tagName + '.' + (e.className||'').toString().trim().split(/\s+/)[0]
             + ' right=' + Math.round(e.getBoundingClientRect().right));
      return JSON.stringify({
        clientW: d.clientWidth,
        docScrollW: d.scrollWidth,
        bodyScrollW: b.scrollWidth,
        overflowsX: d.scrollWidth > d.clientWidth,
        byPx: d.scrollWidth - d.clientWidth,
        culprits: over,
      });
    })()''');
    print('${r[0]}x${r[1]} -> $m');
  }
  await client.close();
}
