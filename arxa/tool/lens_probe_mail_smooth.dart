// lens_probe_mail_smooth.dart — measure pill follow-lag + tilt under SMOOTH
// cursor motion (120 CDP moves x 5px every 8ms ~= 600px/s), the way a human
// sweeps. The old 40px-jump sweep masked the follow-factor difference; this
// one exposes it. Run against BOTH urls and compare maxLag/maxTilt.
// Usage: dart run tool/lens_probe_mail_smooth.dart <url> <outDir> <tag> [w] [h]
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

// per-frame sampler: pill visual center + rotation
String _armJs() {
  return r"""
(() => {
  let pill = null;
  window.__SS = [];
  window.__ST0 = performance.now();
  const snap = () => {
    if (!pill) pill = [...document.querySelectorAll('div')].find(d => (d.textContent || '').trim() === 'Copy our email' && getComputedStyle(d).borderRadius === '100px');
    if (pill) {
      const r = pill.getBoundingClientRect();
      const tr = getComputedStyle(pill).transform;
      let rot = 0;
      const m = tr.match(/matrix\(([^)]+)\)/);
      if (m) {
        const p = m[1].split(',').map(parseFloat);
        rot = Math.atan2(p[1], p[0]) * 180 / Math.PI;
      }
      window.__SS.push({ t: Math.round(performance.now() - window.__ST0), x: +(r.x + r.width / 2).toFixed(1), rot: +rot.toFixed(3) });
    }
    if (performance.now() - window.__ST0 < 2500) requestAnimationFrame(snap);
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
    await tab.evaluate("(() => { window.scrollTo(0, document.body.scrollHeight); return window.scrollY; })()");
    await Future.delayed(const Duration(milliseconds: 1500));

    final mail = _jd(await tab.evaluate(_findJs()));
    if (mail is! Map || mail['found'] != true) {
      result['error'] = 'mail not found';
      File(outDir + '/' + tag + '-smooth.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
      stdout.writeln('mail not found');
      return;
    }
    final cx = (mail['cx'] as num).toDouble();
    final cy = (mail['cy'] as num).toDouble();

    await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': 5.0, 'y': 5.0 });
    await Future.delayed(const Duration(milliseconds: 400));
    // enter at left end of the sweep
    await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': cx - 300.0, 'y': cy });
    await Future.delayed(const Duration(milliseconds: 1200)); // entrance settles fully

    await tab.evaluate(_armJs());
    // SMOOTH sweep: 120 moves x 5px every ~8ms => 600px over ~1s
    final t0 = DateTime.now().millisecondsSinceEpoch;
    for (var i = 1; i <= 120; i++) {
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': cx - 300.0 + (5.0 * i), 'y': cy });
      final target = t0 + i * 8;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (target > now) await Future.delayed(Duration(milliseconds: target - now));
    }
    final sweepEnd = DateTime.now().millisecondsSinceEpoch - t0;
    await Future.delayed(const Duration(milliseconds: 800));
    result['sweepEndMs'] = sweepEnd;

    final raw = await tab.evaluate("(() => JSON.stringify(window.__SS || []))()");
    final series = _jd(raw);
    result['series'] = series;
    if (series is List && series.isNotEmpty) {
      double maxLag = 0;
      double maxRot = 0;
      double lagAtEnd = 0;
      for (final s in series) {
        if (s is! Map || s['t'] == null || s['x'] == null || s['rot'] == null) continue;
        final t = (s['t'] as num).toDouble();
        double cursorX;
        if (t >= sweepEnd) {
          cursorX = cx + 300.0;
        } else if (t >= 0) {
          cursorX = cx - 300.0 + (600.0 * t / sweepEnd);
        } else {
          cursorX = cx - 300.0;
        }
        final lag = ((s['x'] as num).toDouble() - cursorX).abs();
        // only count during active sweep
        if (t > 50 && t < sweepEnd && lag > maxLag) maxLag = lag;
        final rot = (s['rot'] as num).abs().toDouble();
        if (t > 50 && t < sweepEnd + 100 && rot > maxRot) maxRot = rot;
        if (t >= sweepEnd && t < sweepEnd + 30) lagAtEnd = lag;
      }
      result['maxLagSmooth'] = maxLag.toStringAsFixed(1);
      result['maxTiltSmooth'] = maxRot.toStringAsFixed(2);
      result['lagAtSweepEnd'] = lagAtEnd.toStringAsFixed(1);
    }
    File(outDir + '/' + tag + '-smooth.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('smooth ok -> ' + outDir + '/' + tag + '-smooth.json maxLag=' + (result['maxLagSmooth'] ?? '?').toString() + ' maxTilt=' + (result['maxTiltSmooth'] ?? '?').toString());
  } finally {
    await client.close();
  }
}
