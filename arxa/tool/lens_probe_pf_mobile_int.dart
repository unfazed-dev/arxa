// lens_probe_pf_mobile_int.dart — ref pricing card internals at 390px.
// Usage: dart run tool/lens_probe_pf_mobile_int.dart <url>
import 'dart:convert';
import 'package:arxa/lens/daemon.dart';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'https://umanodesign.studio/';
  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(390, 844);
    await tab.navigateAndSettle(url, settleMs: 800);
    final w = Stopwatch()..start();
    while (w.elapsedMilliseconds < 30000) {
      final ok = await tab.evaluate(r'''(() => ![...document.querySelectorAll('div')].some(d => { const s = getComputedStyle(d); return s.position === 'fixed' && (s.zIndex === '9999' || s.zIndex === '99999'); }))()''');
      if (ok == true) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await Future.delayed(const Duration(milliseconds: 600));
    final js = r'''
(() => {
  const card = document.querySelector('#pricing a');
  if (!card) return JSON.stringify({ err: 'no card' });
  const info = (el) => {
    if (!el) return null;
    const cs = getComputedStyle(el); const r = el.getBoundingClientRect();
    return { h: +r.height.toFixed(1), w: +r.width.toFixed(1), font: cs.fontSize + '/' + cs.fontWeight + ' lh=' + cs.lineHeight, pad: cs.paddingTop + ' ' + cs.paddingRight + ' ' + cs.paddingBottom + ' ' + cs.paddingLeft, mar: cs.marginTop + ' ' + cs.marginRight + ' ' + cs.marginBottom + ' ' + cs.marginLeft, radius: cs.borderRadius, gap: cs.gap };
  };
  const kids = [...card.children];
  const media = kids[0];
  const body = kids[1];
  const bodyKids = body ? [...body.children] : [];
  return JSON.stringify({
    card: info(card),
    flat: [...card.children].map(info),
    media: info(media),
    body: info(body),
    nameRow: info(bodyKids[0]),
    name: bodyKids[0] ? info(bodyKids[0].children[0]) : null,
    price: bodyKids[0] ? info(bodyKids[0].children[1]) : null,
    desc: info(bodyKids[1]),
    feats: info(bodyKids[2]),
    feat0: bodyKids[2] && bodyKids[2].children[0] ? info(bodyKids[2].children[0]) : null,
    feat0span: bodyKids[2] && bodyKids[2].children[0] ? info(bodyKids[2].children[0].children[1]) : null,
    cta: info(bodyKids[3])
  });
})()
''';
    print(await tab.evaluate(js));
  } finally {
    await client.close();
  }
}
