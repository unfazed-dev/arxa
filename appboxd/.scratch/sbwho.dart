import 'dart:async';
import 'package:appboxd/cdp.dart';

Future<void> main() async {
  final client = await CdpClient.launch();
  final s = await client.newTab();
  await s.enable();
  for (final r in [[390, 844], [744, 1133]]) {
    await s.setViewport(r[0], r[1]);
    await s.navigate('http://127.0.0.1:4319/');
    await Future<void>.delayed(const Duration(seconds: 3));
    final m = await s.evaluate(r'''(() => {
      const hits = [];
      for (const e of document.querySelectorAll('*')) {
        const cs = getComputedStyle(e);
        const canY = /auto|scroll/.test(cs.overflowY);
        const canX = /auto|scroll/.test(cs.overflowX);
        if (!canX && !canY) continue;
        const barY = e.offsetWidth - e.clientWidth;   // px a vertical bar eats
        const barX = e.offsetHeight - e.clientHeight; // px a horizontal bar eats
        const overX = e.scrollWidth > e.clientWidth + 1;
        const overY = e.scrollHeight > e.clientHeight + 1;
        if (barX > 0 || barY > 0 || overX || overY) {
          hits.push({
            el: e.tagName + '.' + (e.className||'').toString().trim().split(/\s+/)[0],
            ox: cs.overflowX, oy: cs.overflowY,
            barPxX: barX, barPxY: barY, overX, overY,
            sbw: cs.scrollbarWidth,
          });
        }
      }
      return JSON.stringify(hits.slice(0, 6), null, 0);
    })()''');
    print('${r[0]}x${r[1]}:');
    print('  $m');
  }
  await client.close();
}
