// lens_probe_seam4.dart — dark-region anatomy: every large #0a0d12 element
// with its border-box rect, radius and margin, plus an edge-inset profile
// of the last one (min inset d where the dark sheet covers the point, at
// several heights above its bottom edge). Run on both sites.
// Usage: dart run tool/lens_probe_seam4.dart <url> [w] [h] [outJson]
import 'dart:convert';
import 'dart:io';

import 'package:arxa/lens/daemon.dart';

String _revealJs() {
  return r'''
(() => {
  const overlay = [...document.querySelectorAll('div')].find(d => {
    const s = getComputedStyle(d);
    return s.position === 'fixed' && (s.zIndex === '9999' || s.zIndex === '99999');
  });
  return !overlay;
})()
''';
}

String _anatomyJs() {
  return r'''
(() => {
  const darks = [...document.querySelectorAll('body *')].filter(e => { const s = getComputedStyle(e); const r = e.getBoundingClientRect(); return s.backgroundColor === 'rgb(10, 13, 18)' && r.height > 400 && r.width > 400; });
  const list = darks.map(e => { const s = getComputedStyle(e); const r = e.getBoundingClientRect(); const c = e.className; return { tag: e.tagName, cls: String(c && c.baseVal !== undefined ? c.baseVal : c).slice(0, 50), x: Math.round(r.x), y: Math.round(r.y + window.scrollY), w: Math.round(r.width), h: Math.round(r.height), radius: s.borderRadius, margin: s.margin }; });
  const last = darks[darks.length - 1];
  const out = { darks: list };
  if (last) {
    const rb = last.getBoundingClientRect();
    const W = window.innerWidth;
    const darkAt = (x, y) => document.elementsFromPoint(x, y).some(e => { const s = getComputedStyle(e); const r = e.getBoundingClientRect(); return s.backgroundColor === 'rgb(10, 13, 18)' && r.height > 400; });
    const prof = [];
    for (const dy of [4, 20, 50, 100, 200, 300, 500]) {
      const y = rb.bottom - dy;
      if (y < rb.top) break;
      let minR = -1, minL = -1;
      for (let d = 0; d <= 30; d += 2) { if (minR < 0 && darkAt(W - 1 - d, y)) minR = d; if (minL < 0 && darkAt(d, y)) minL = d; if (minR >= 0 && minL >= 0) break; }
      prof.push({ dy, minL, minR });
    }
    out.lastCls = String(last.className).slice(0, 50);
    out.profile = prof;
  }
  return JSON.stringify(out);
})()
''';
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final width = args.length > 1 ? int.parse(args[1]) : 1713;
  final height = args.length > 2 ? int.parse(args[2]) : 1098;
  final outPath = args.length > 3 ? args[3] : '/tmp/arxa-compare/seam/probe4.json';
  final result = <String, dynamic>{ 'url': url, 'viewport': '$width x $height' };
  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: 700);
    final w = Stopwatch()..start();
    while (w.elapsedMilliseconds < 30000) {
      final ok = await tab.evaluate(_revealJs());
      if (ok == true) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await Future.delayed(const Duration(milliseconds: 600));
    result['anatomy'] = await tab.evaluate(_anatomyJs());
    File(outPath).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('probe seam4 ok -> ' + outPath);
  } finally {
    await client.close();
  }
}