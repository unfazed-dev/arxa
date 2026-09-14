// lens_probe_cta.dart — pricing CTA computed style (radius/bg/font), any scroll.
// Usage: dart run tool/lens_probe_cta.dart <url>
import 'dart:convert';
import 'dart:io';
import 'package:arxa/lens/daemon.dart';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'https://umanodesign.studio/';
  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1713, 1098);
    await tab.navigateAndSettle(url, settleMs: 800);
    final w = Stopwatch()..start();
    while (w.elapsedMilliseconds < 30000) {
      final ok = await tab.evaluate(r'''(() => ![...document.querySelectorAll('div')].some(d => { const s = getComputedStyle(d); return s.position === 'fixed' && (s.zIndex === '9999' || s.zIndex === '99999'); }))()''');
      if (ok == true) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await Future.delayed(const Duration(milliseconds: 500));
    final js = r'''
(() => {
  const cta = [...document.querySelectorAll('#pricing a div')].find(d => (d.textContent || '').trim() === 'Book a call' && d.children.length === 0);
  if (!cta) return JSON.stringify({ err: 'no cta' });
  const cs = getComputedStyle(cta);
  const r = cta.getBoundingClientRect();
  return JSON.stringify({ tag: cta.tagName.toLowerCase(), rect: { w: +r.width.toFixed(1), h: +r.height.toFixed(1) }, radius: cs.borderRadius, bg: cs.backgroundColor, color: cs.color, font: cs.fontSize + '/' + cs.fontWeight + ' ' + cs.fontFamily.split(',')[0], lh: cs.lineHeight, pad: cs.paddingTop + ' ' + cs.paddingRight + ' ' + cs.paddingBottom + ' ' + cs.paddingLeft, mar: cs.marginTop + ' ' + cs.marginRight + ' ' + cs.marginBottom + ' ' + cs.marginLeft });
})()
''';
    print(await tab.evaluate(js));
  } finally {
    await client.close();
  }
}
