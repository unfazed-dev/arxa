// lens_probe_mail_law.dart — nail the ref pill's tilt law: tilt vs cursor
// offset (dx) from the mail's center. Park at each dx, sample settled tilt,
// and check (a) linearity (b) clamp (c) hold-vs-decay over a 2s park.
// Usage: dart run tool/lens_probe_mail_law.dart <url> <outDir> <tag> [w] [h]
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
  return JSON.stringify({ found: true, cx: Math.round(r.x + r.width / 2), cy: Math.round(r.y + r.height / 2), w: Math.round(r.width) });
})()
""";
}

String _snapJs() {
  return r"""
(() => {
  const pill = [...document.querySelectorAll('div')].find(d => (d.textContent || '').trim() === 'Copy our email' && getComputedStyle(d).borderRadius === '100px');
  if (!pill) return JSON.stringify({ found: false });
  const r = pill.getBoundingClientRect();
  const tr = getComputedStyle(pill).transform;
  let rot = 0;
  const m = tr.match(/matrix\(([^)]+)\)/);
  if (m) {
    const p = m[1].split(',').map(parseFloat);
    rot = Math.atan2(p[1], p[0]) * 180 / Math.PI;
  }
  return JSON.stringify({ found: true, x: +(r.x + r.width / 2).toFixed(1), rot: +rot.toFixed(3) });
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
  final url = args.isNotEmpty ? args[0] : 'https://umanodesign.studio/';
  final outDir = args.length > 1 ? args[1] : '/tmp/arxa-compare/mail';
  final tag = args.length > 2 ? args[2] : 'mail-ref';
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
    await tab.evaluate("(() => { window.scrollTo(0, document.body.scrollHeight); return window.scrollY; })()");
    await Future.delayed(const Duration(milliseconds: 1500));

    final mail = _jd(await tab.evaluate(_findJs()));
    if (mail is! Map || mail['found'] != true) {
      result['error'] = 'mail not found';
      File(outDir + '/' + tag + '-law.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
      stdout.writeln('mail not found');
      return;
    }
    final cx = (mail['cx'] as num).toDouble();
    final cy = (mail['cy'] as num).toDouble();
    result['mail'] = mail;

    final dxs = [-700.0, -600.0, -400.0, -300.0, -200.0, -100.0, 0.0, 100.0, 200.0, 300.0, 400.0, 600.0, 700.0];
    final table = <dynamic>[];
    for (final dx in dxs) {
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': cx + dx, 'y': cy });
      await Future.delayed(const Duration(milliseconds: 700)); // settle fully
      final s = _jd(await tab.evaluate(_snapJs()));
      if (s is Map && s['found'] == true) {
        table.add({ 'dx': dx, 'rot': s['rot'], 'pillX': s['x'] });
      } else {
        table.add({ 'dx': dx, 'error': 'no pill' });
      }
    }
    result['table'] = table;

    // hold test: park at -400 for 2.5s, sample every 500ms
    await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': cx - 400.0, 'y': cy });
    final hold = <dynamic>[];
    for (var i = 0; i < 6; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final s = _jd(await tab.evaluate(_snapJs()));
      if (s is Map && s['found'] == true) hold.add({ 'ms': (i + 1) * 500, 'rot': s['rot'] });
    }
    result['hold'] = hold;

    File(outDir + '/' + tag + '-law.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('law ok -> ' + outDir + '/' + tag + '-law.json');
  } finally {
    await client.close();
  }
}
