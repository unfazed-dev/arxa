// lens_probe_mail_tilt.dart — decide WHERE the mail pill's tilt disappears:
// style (JS) -> computed style -> PAINT. Two passes: A normal (filled 'scale'
// animation from copyTooltipIn active), B pill.style.animation='none' (fill
// killed). Per-frame sampler records style.transform + computed transform/
// rotate/scale; screenshots taken right after each sweep show the PAINT.
// Usage: dart run tool/lens_probe_mail_tilt.dart <url> <outDir> <tag> [w] [h]
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
  if (!el) return JSON.stringify({ found: false });
  const r = el.getBoundingClientRect();
  return JSON.stringify({ found: true, cx: Math.round(r.x + r.width / 2), cy: Math.round(r.y + r.height / 2) });
})()
""";
}

String _armJs() {
  return """
(() => {
  let pill = null;
  window.__TS = [];
  window.__TT0 = performance.now();
  const snap = () => {
    if (!pill) pill = [...document.querySelectorAll('div')].find(d => (d.textContent || '').trim() === 'Copy our email' && getComputedStyle(d).borderRadius === '100px');
    if (pill) {
      const cs = getComputedStyle(pill);
      window.__TS.push({
        t: Math.round(performance.now() - window.__TT0),
        style: pill.style.transform || '',
        comp: cs.transform,
        rotProp: cs.rotate || '',
        scaleProp: cs.scale || '',
        anim: cs.animationName + '/' + cs.animationPlayState
      });
    }
    if (performance.now() - window.__TT0 < 1800) requestAnimationFrame(snap);
  };
  requestAnimationFrame(snap);
  return 'armed';
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

double _maxRot(dynamic series) {
  double m = 0;
  if (series is! List) return m;
  for (final s in series) {
    final tr = (s['comp'] ?? '') as String;
    final match = RegExp(r'matrix\(([^)]+)\)').firstMatch(tr);
    if (match == null) continue;
    final p = match.group(1)!.split(',').map((s) => double.parse(s.trim())).toList();
    if (p.length < 2) continue;
    final rot = (math.atan2(p[1], p[0]) * 180 / math.pi).abs();
    if (rot > m) m = rot;
  }
  return m;
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final outDir = args.length > 1 ? args[1] : '/tmp/arxa-compare/mail';
  final tag = args.length > 2 ? args[2] : 'mail-ours';
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
      File(outDir + '/' + tag + '-tilt.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
      stdout.writeln('mail not found');
      return;
    }
    final cx = (mail['cx'] as num).toDouble();
    final cy = (mail['cy'] as num).toDouble();

    await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': 5.0, 'y': 5.0 });
    await Future.delayed(const Duration(milliseconds: 400));

    // PASS A: entrance + sweep with the filled scale animation intact
    await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': cx, 'y': cy });
    await Future.delayed(const Duration(milliseconds: 1100));
    await tab.evaluate(_armJs());
    for (var i = 0; i <= 8; i++) {
      final x = cx - 240 + (480.0 * i / 8);
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': x, 'y': cy });
      await Future.delayed(const Duration(milliseconds: 60));
    }
    final dumpA = _jd(await tab.evaluate("(() => JSON.stringify(window.__TS || []))()"));
    final shotA = await tab.screenshot();
    File(outDir + '/' + tag + '-tilt-A.png').writeAsBytesSync(shotA);
    await Future.delayed(const Duration(milliseconds: 400));

    // PASS B: kill the animation fill (scale no longer animated/held)
    await tab.evaluate("(() => { const p = [...document.querySelectorAll('div')].find(d => (d.textContent || '').trim() === 'Copy our email' && getComputedStyle(d).borderRadius === '100px'); if (p) { p.style.animation = 'none'; } return 1; })()");
    await tab.evaluate(_armJs());
    await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': 5.0, 'y': 5.0 });
    await Future.delayed(const Duration(milliseconds: 300));
    await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': cx, 'y': cy });
    await Future.delayed(const Duration(milliseconds: 300));
    for (var i = 0; i <= 8; i++) {
      final x = cx + 240 - (480.0 * i / 8);
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': x, 'y': cy });
      await Future.delayed(const Duration(milliseconds: 60));
    }
    final dumpB = _jd(await tab.evaluate("(() => JSON.stringify(window.__TS || []))()"));
    final shotB = await tab.screenshot();
    File(outDir + '/' + tag + '-tilt-B.png').writeAsBytesSync(shotB);

    result['passA'] = { 'samples': dumpA is List ? dumpA.length : 0, 'maxRotDeg': _maxRot(dumpA).toStringAsFixed(2), 'last': dumpA is List && dumpA.isNotEmpty ? dumpA.last : null };
    result['passB'] = { 'samples': dumpB is List ? dumpB.length : 0, 'maxRotDeg': _maxRot(dumpB).toStringAsFixed(2), 'last': dumpB is List && dumpB.isNotEmpty ? dumpB.last : null };
    result['seriesA'] = dumpA;
    result['seriesB'] = dumpB;
    File(outDir + '/' + tag + '-tilt.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('tilt ok -> ' + outDir + '/' + tag + '-tilt.json');
  } finally {
    await client.close();
  }
}
