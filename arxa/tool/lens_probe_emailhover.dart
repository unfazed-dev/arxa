// lens_probe_emailhover.dart — the reference giant email's real hover:
// mouseMoved onto the email text, sampling fill/color/transform of the svg
// text node at rAF rate + getAnimations inventory.
// Usage: dart run tool/lens_probe_emailhover.dart <url> <outJson>
import 'dart:convert';
import 'dart:io';
import 'package:arxa/lens/daemon.dart';

String _revealJs() {
  return r"""
(() => {
  const overlay = [...document.querySelectorAll('div')].find(d => {
    const s = getComputedStyle(d);
    return s.position === 'fixed' && (s.zIndex === '9999' || s.zIndex === '99999');
  });
  return !overlay;
})()
""";
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'https://umanodesign.studio/';
  final outJson = args.length > 1 ? args[1] : '/tmp/arxa-compare/pf/emailhover.json';
  final result = <String, dynamic>{};
  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1713, 1098);
    await tab.navigateAndSettle(url, settleMs: 700);
    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < 30000) {
      final ok = await tab.evaluate(_revealJs());
      if (ok == true) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await Future.delayed(const Duration(milliseconds: 700));
    await tab.evaluate(r"(() => { const btn = [...document.querySelectorAll('button')].find(b => /^(accept)$/i.test((b.textContent || '').trim())); if (btn) btn.click(); return 1; })()");
    await Future.delayed(const Duration(milliseconds: 300));
    await tab.evaluate(r"(() => { window.scrollTo(0, document.body.scrollHeight); return window.scrollY; })()");
    await Future.delayed(const Duration(milliseconds: 1200));
    final arm = await tab.evaluate(r"""
(() => {
  const f = document.querySelector('footer');
  const t = [...f.querySelectorAll('text')].find(t => /@/.test(t.textContent || ''));
  if (!t) return 'missing';
  window.__HA = [];
  window.__HAN = null;
  const t0 = performance.now();
  const snap = () => {
    const cs = getComputedStyle(t);
    window.__HA.push({ t: Math.round(performance.now() - t0), fill: cs.fill, c: cs.color, op: cs.opacity, tr: cs.transform });
    if (performance.now() - t0 < 900) requestAnimationFrame(snap);
  };
  requestAnimationFrame(snap);
  setTimeout(() => { window.__HAN = (t.getAnimations ? t.getAnimations() : []).map(a => { const ct = a.effect ? a.effect.getComputedTiming() : null; return { cls: a.constructor.name, prop: a.transitionProperty || null, dur: ct ? ct.duration : null, ease: ct ? ct.easing : null }; }); }, 80);
  const r = t.getBoundingClientRect();
  window.__PT = [r.x + r.width / 2, r.y + r.height / 2];
  return 'armed';
})()
""");
    result['arm'] = arm is String ? arm : jsonEncode(arm);
    final pt = await tab.evaluate(r"(() => JSON.stringify(window.__PT || null))()");
    final coords = jsonDecode(pt is String ? pt : jsonEncode(pt));
    if (coords is List && coords.length == 2) {
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': (coords[0] as num).toDouble(), 'y': (coords[1] as num).toDouble() });
      await Future.delayed(const Duration(milliseconds: 900));
      final col = await tab.evaluate(r"(() => JSON.stringify({ anims: window.__HAN || null, samples: window.__HA || null }))()");
      result['hover'] = jsonDecode(col is String ? col : jsonEncode(col));
    }
    File(outJson).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('emailhover ok -> ' + outJson);
  } finally {
    await client.close();
  }
}

