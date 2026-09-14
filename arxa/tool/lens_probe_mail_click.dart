// lens_probe_mail_click.dart — the ref's pill state machine around CLICK:
// pill dumps at rest-hover, +200ms, +700ms, +1600ms after the click, with
// full HTML (600 chars) so text/icon/colors are captured per state.
// Usage: dart run tool/lens_probe_mail_click.dart <url> <outDir> <tag> [w] [h]
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

String _acceptJs() {
  return r"""
(() => { const btn = [...document.querySelectorAll('button')].find(b => /^(accept)$/i.test((b.textContent || '').trim())); if (btn) btn.click(); return 1; })()
""";
}

String _findJs() {
  return r"""
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

String _pillJs() {
  return r"""
(() => {
  const out = [];
  const els = [...document.querySelectorAll('div, span')];
  for (const e of els) {
    const cs = getComputedStyle(e);
    const r = e.getBoundingClientRect();
    if (r.width === 0 || r.height === 0 || r.width > 500 || r.height > 160) continue;
    if (cs.position !== 'fixed' && cs.position !== 'absolute') continue;
    if (!(parseFloat(cs.borderRadius) >= 40 || (e.textContent || '').includes('Cop'))) continue;
    out.push({ x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height), text: (e.textContent || '').trim().slice(0, 40), bg: cs.backgroundColor, color: cs.color, opacity: cs.opacity, radius: cs.borderRadius, anim: cs.animationName + ' ' + cs.animationDuration + ' ' + cs.animationTimingFunction + ' ' + cs.animationFillMode, html: (e.outerHTML || '').slice(0, 1500), span: (function(){ const s = e.querySelector('span'); if (!s) return null; const c = getComputedStyle(s); return { fontSize: c.fontSize, fontWeight: c.fontWeight, color: c.color, family: c.fontFamily.slice(0, 40) }; })() });
    if (out.length >= 4) break;
  }
  return JSON.stringify(out);
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
  final outDir = args.length > 1 ? args[1] : '/tmp/arxa-compare/mail';
  final tag = args.length > 2 ? args[2] : 'mail';
  final w = args.length > 3 ? int.parse(args[3]) : 1713;
  final h = args.length > 4 ? int.parse(args[4]) : 1098;
  Directory(outDir).createSync(recursive: true);
  final result = <String, dynamic>{ 'url': url, 'tag': tag };
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
    await tab.evaluate(r"(() => { window.scrollTo(0, document.body.scrollHeight); return window.scrollY; })()");
    await Future.delayed(const Duration(milliseconds: 1500));

    final mail = _jd(await tab.evaluate(_findJs()));
    if (mail is Map && mail['found'] == true) {
      final cx = (mail['cx'] as num).toDouble();
      final cy = (mail['cy'] as num).toDouble();
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': 5.0, 'y': 5.0 });
      await Future.delayed(const Duration(milliseconds: 400));
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': cx, 'y': cy });
      await Future.delayed(const Duration(milliseconds: 900));
      result['hoverRest'] = _jd(await tab.evaluate(_pillJs()));
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mousePressed', 'x': cx, 'y': cy, 'button': 'left', 'clickCount': 1 });
      await Future.delayed(const Duration(milliseconds: 60));
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseReleased', 'x': cx, 'y': cy, 'button': 'left', 'clickCount': 1 });
      await Future.delayed(const Duration(milliseconds: 160));
      result['click200'] = _jd(await tab.evaluate(_pillJs()));
      File(outDir + '/' + tag + '-click200.png').writeAsBytesSync(await tab.screenshot());
      await Future.delayed(const Duration(milliseconds: 500));
      result['click700'] = _jd(await tab.evaluate(_pillJs()));
      await Future.delayed(const Duration(milliseconds: 900));
      result['click1600'] = _jd(await tab.evaluate(_pillJs()));
      File(outDir + '/' + tag + '-click1600.png').writeAsBytesSync(await tab.screenshot());
    }
    File(outDir + '/' + tag + '-click.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('click ok -> ' + outDir + '/' + tag + '-click.json');
  } finally {
    await client.close();
  }
}
