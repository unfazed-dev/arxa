// lens_probe_mail_textwidth.dart — measure the giant email text node's ink
// box (Range around the first text node) + computed font-size, to derive the
// exact fit-width law for the replica.
// Usage: dart run tool/lens_probe_mail_textwidth.dart <url> [w] [h]
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
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final w = args.length > 1 ? int.parse(args[1]) : 1713;
  final h = args.length > 2 ? int.parse(args[2]) : 1098;
  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(w, h);
    await tab.navigateAndSettle(url, settleMs: 700);
    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < 30000) {
      final ok = await tab.evaluate(_revealJs());
      if (ok == true) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await Future.delayed(const Duration(milliseconds: 500));
    await tab.evaluate(r"(() => { const b = [...document.querySelectorAll('button')].find(b => /^(accept)$/i.test((b.textContent || '').trim())); if (b) b.click(); return 1; })()");
    await tab.evaluate(r"(() => { window.scrollTo(0, document.body.scrollHeight); return 1; })()");
    await Future.delayed(const Duration(milliseconds: 1200));
    final r = await tab.evaluate(r"""
(() => {
  const el = document.querySelector('[data-footer-email]');
  if (!el) return JSON.stringify({ found: false });
  const node = [...el.childNodes].find(n => n.nodeType === 3 && /@/.test(n.textContent || ''));
  if (!node) return JSON.stringify({ found: false });
  const range = document.createRange();
  range.selectNodeContents(node);
  const rect = range.getBoundingClientRect();
  const cs = getComputedStyle(el);
  const drect = el.getBoundingClientRect();
  return JSON.stringify({
    text: (node.textContent || '').trim(),
    chars: (node.textContent || '').trim().length,
    x: +rect.x.toFixed(1), y: +rect.y.toFixed(1), w: +rect.width.toFixed(1), h: +rect.height.toFixed(1),
    font: cs.fontSize, weight: cs.fontWeight, ls: cs.letterSpacing,
    divX: +drect.x.toFixed(1), divW: +drect.width.toFixed(1),
    footerH: (document.querySelector('.site-footer') || {}).offsetHeight || 0
  });
})()
""");
    var x = r;
    while (x is String) {
      final t = x.trim();
      if (!t.startsWith('{')) break;
      try { x = jsonDecode(x); } catch (_) { break; }
    }
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(x));
  } finally {
    await client.close();
  }
}
