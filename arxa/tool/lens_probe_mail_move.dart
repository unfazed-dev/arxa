// lens_probe_mail_move.dart — quantify the mail pill's FOLLOW dynamics on
// both sides: (a) entry — per-frame pill width during the 0.4s spring-in
// (overshoot ratio); (b) sweep — 12-step 600ms mouse sweep across the mail
// with a per-frame sampler on pill center + rotate, giving max lag (px) and
// max tilt (deg) and settle time. Usage:
// dart run tool/lens_probe_mail_move.dart <url> <outDir> <tag> [w] [h]
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

// arm a per-frame sampler on the pill (found by its label)
String _armJs() {
  return r"""
(() => {
  let pill = null;
  window.__PS = [];
  window.__PT0 = performance.now();
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
    window.__PS.push({ t: Math.round(performance.now() - window.__PT0), x: +(r.x + r.width / 2).toFixed(1), y: +(r.y + r.height / 2).toFixed(1), w: +r.width.toFixed(1), rot: +rot.toFixed(3) });
    }
    if (performance.now() - window.__PT0 < 2200) requestAnimationFrame(snap);
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
    await tab.evaluate(r"(() => { window.scrollTo(0, document.body.scrollHeight); return window.scrollY; })()");
    await Future.delayed(const Duration(milliseconds: 1500));

    final mail = _jd(await tab.evaluate(_findJs()));
    if (mail is! Map || mail['found'] != true) {
      result['error'] = 'mail not found';
      File(outDir + '/' + tag + '-move.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
      stdout.writeln('mail not found');
      return;
    }
    final cx = (mail['cx'] as num).toDouble();
    final cy = (mail['cy'] as num).toDouble();

    await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': 5.0, 'y': 5.0 });
    await Future.delayed(const Duration(milliseconds: 500));

    // (a) ENTRY: arm sampler, jump onto the mail, let the spring-in play
    result['armed'] = await tab.evaluate(_armJs());
    await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': cx, 'y': cy });
    await Future.delayed(const Duration(milliseconds: 1100));

    // (b) SWEEP: 12 steps x 50ms across the mail, sampler still running
    for (var i = 0; i <= 12; i++) {
      final x = cx - 240 + (480.0 * i / 12);
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': x, 'y': cy });
      await Future.delayed(const Duration(milliseconds: 50));
    }
    // (c) SETTLE: hold still, sampler keeps running
    await Future.delayed(const Duration(milliseconds: 700));

    final raw = await tab.evaluate(r"(() => JSON.stringify(window.__PS || []))()");
    final series = _jd(raw);
    // cursor timeline: entry t0 -> (cx,cy); sweep starts ~1100ms, step 50ms; ends ~1700ms
    result['series'] = series;
    // derived metrics
    if (series is List && series.isNotEmpty) {
      final base = series.firstWhere((s) => s['w'] > 100, orElse: () => series.last)['w'] as num;
      double maxW = 0;
      for (final s in series) {
        if ((s['w'] as num) > maxW) maxW = (s['w'] as num).toDouble();
      }
      result['entryOvershoot'] = (maxW / base).toStringAsFixed(3);
      double maxLag = 0;
      double maxRot = 0;
      for (final s in series) {
        final t = s['t'] as int;
        double cursorX = cx;
        if (t > 1700) cursorX = cx + 240;
        else if (t > 1100) cursorX = cx - 240 + (480.0 * (t - 1100) / 600);
        final lag = ((s['x'] as num) - cursorX).abs().toDouble();
        if (t > 1100 && t < 1750 && lag > maxLag) maxLag = lag;
        final rot = (s['rot'] as num).abs().toDouble();
        if (rot > maxRot) maxRot = rot;
      }
      result['maxLagSweep'] = maxLag.toStringAsFixed(1);
      result['maxTiltDeg'] = maxRot.toStringAsFixed(2);
      // settle: last t where |x - (cx+240)| > 4 after sweep end
      int settle = -1;
      for (final s in series) {
        final t = s['t'] as int;
        if (t > 1700 && ((s['x'] as num) - (cx + 240)).abs() > 4) settle = t;
      }
      result['settleAfterSweepEnd'] = settle < 0 ? 0 : settle - 1700;
    }
    File(outDir + '/' + tag + '-move.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('move ok -> ' + outDir + '/' + tag + '-move.json');
  } finally {
    await client.close();
  }
}
