// lens_probe_mail_park.dart — park the cursor at a fixed offset from the
// mail center, let everything settle, screenshot the pill region. The
// see-saw state the user actually sees. Run per side, then composite.
// Usage: dart run tool/lens_probe_mail_park.dart <url> <outPath> [dx] [w] [h]
import 'dart:convert';
import 'dart:io';

import 'package:arxa/lens/daemon.dart';

String _revealJs() {
  return """
(() => {
  const overlay = [...document.querySelectorAll('div')].find(d => {
    const s = getComputedStyle(d);
    return s.position === 'fixed' && (s.zIndex === '9999' || s.zIndex === '99999');
  });
  return !overlay;
})()
""";
}

String _acceptJs() {
  return r"""
(() => { const btn = [...document.querySelectorAll('button')].find(b => /^(accept)$/i.test((b.textContent || '').trim())); if (btn) btn.click(); return 1; })()
""";
}

String _findJs() {
  return """
(() => {
  const f = document.querySelector('footer') || document.body;
  let el = f.querySelector('[data-footer-email]');
  if (!el) el = [...f.querySelectorAll('text, tspan')].find(t => /@/.test(t.textContent || ''));
  if (!el) return JSON.stringify({ found: false });
  const r = el.getBoundingClientRect();
  return JSON.stringify({ found: true, cx: Math.round(r.x + r.width / 2), cy: Math.round(r.y + r.height / 2) });
})()
""";
}

dynamic _jd(dynamic v) {
  var x = v;
  while (x is String) {
    final t = x.trim();
    if (!t.startsWith('{') && !t.startsWith('[')) break;
    try { x = jsonDecode(x); } catch (_) { break; }
  }
  return x;
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final outPath = args.length > 1 ? args[1] : '/tmp/arxa-compare/mail/park.png';
  final dx = args.length > 2 ? double.parse(args[2]) : -400.0;
  final w = args.length > 3 ? int.parse(args[3]) : 1713;
  final h = args.length > 4 ? int.parse(args[4]) : 1098;
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
    await Future.delayed(const Duration(milliseconds: 700));
    await tab.evaluate(_acceptJs());
    await Future.delayed(const Duration(milliseconds: 300));
    await tab.evaluate("(() => { window.scrollTo(0, document.body.scrollHeight); return window.scrollY; })()");
    await Future.delayed(const Duration(milliseconds: 1500));
    final mail = _jd(await tab.evaluate(_findJs()));
    if (mail is! Map || mail['found'] != true) {
      stdout.writeln('mail not found');
      return;
    }
    final cx = (mail['cx'] as num).toDouble();
    final cy = (mail['cy'] as num).toDouble();
    await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': cx + dx, 'y': cy });
    await Future.delayed(const Duration(milliseconds: 1200));
    File(outPath).writeAsBytesSync(await tab.screenshot());
    stdout.writeln('park ok -> ' + outPath + ' (pill near ' + (cx + dx).round().toString() + ',' + cy.round().toString() + ')');
  } finally {
    await client.close();
  }
}
