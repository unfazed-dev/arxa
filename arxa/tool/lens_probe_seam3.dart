// lens_probe_seam3.dart — the dark region's BOTTOM seam (dark → light
// footer) on both sites: corner coverage scan above the footer's top
// edge plus white-peek scan and screenshot. Tells whether the reference
// rounds the dark region's bottom corners while keeping the top square.
// Usage: dart run tool/lens_probe_seam3.dart <url> [w] [h] [outJson]
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

String _bottomJs() {
  return r'''
(() => {
  const isLight = (e) => { const s = getComputedStyle(e); const m = s.backgroundColor; if (m.indexOf('rgb') !== 0) return false; const t = m.replace('rgba(', '').replace('rgb(', '').replace(')', '').split(',').map(x => parseFloat(x)); const a = t.length > 3 ? t[3] : 1; return a > 0.9 && t[0] > 225 && t[1] > 225 && t[2] > 225; };
  const cands = [...document.querySelectorAll('footer, body *')].filter(e => { const r = e.getBoundingClientRect(); return isLight(e) && r.height > 300 && r.width > 800; });
  const foot = cands.length ? cands[cands.length - 1] : null;
  if (!foot) return JSON.stringify({ err: 'no light footer block' });
  const fr = foot.getBoundingClientRect();
  const W = window.innerWidth;
  const darkAt = (x, y) => document.elementsFromPoint(x, y).some(e => { const s = getComputedStyle(e); const r = e.getBoundingClientRect(); return s.backgroundColor === 'rgb(10, 13, 18)' && r.height > 400; });
  const right = [], left = [], rowR = [], rowL = [];
  for (let dy = 0; dy <= 48; dy += 2) { right.push(darkAt(W - 2, fr.top - 1 - dy) ? 1 : 0); left.push(darkAt(2, fr.top - 1 - dy) ? 1 : 0); }
  for (let d = 0; d <= 48; d += 2) { rowR.push(darkAt(W - d, fr.top - 2) ? 1 : 0); rowL.push(darkAt(d, fr.top - 2) ? 1 : 0); }
  const cls = String(foot.className && foot.className.baseVal !== undefined ? foot.className.baseVal : foot.className).slice(0, 60);
  return JSON.stringify({ footCls: foot.tagName + '.' + cls, footTop: Math.round(fr.top), footBg: getComputedStyle(foot).backgroundColor, right: right.join(''), left: left.join(''), rowR: rowR.join(''), rowL: rowL.join('') });
})()
''';
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final width = args.length > 1 ? int.parse(args[1]) : 1713;
  final height = args.length > 2 ? int.parse(args[2]) : 1098;
  final outPath = args.length > 3 ? args[3] : '/tmp/arxa-compare/seam/probe3.json';
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
    await Future.delayed(const Duration(milliseconds: 800));
    await tab.evaluate(r'''(() => { const btn = [...document.querySelectorAll('button')].find(b => /^(accept)$/i.test((b.textContent || '').trim())); if (btn) btn.click(); return !!btn; })()''');
    await Future.delayed(const Duration(milliseconds: 400));
    // scroll to the page end so the footer is fully in view, then pull back
    // up until the footer top sits at 0.5 vh
    await tab.evaluate(r'''(() => { window.scrollTo(0, document.documentElement.scrollHeight); return window.scrollY; })()''');
    await Future.delayed(const Duration(milliseconds: 900));
    for (int i = 0; i < 8; i++) {
      final s = await tab.evaluate(r'''(() => { const light = [...document.querySelectorAll('footer, body *')].filter(e => { const st = getComputedStyle(e); if (st.backgroundColor.indexOf('rgb') !== 0) return false; const t = st.backgroundColor.replace('rgba(', '').replace('rgb(', '').replace(')', '').split(',').map(x => parseFloat(x)); const a = t.length > 3 ? t[3] : 1; const r = e.getBoundingClientRect(); return a > 0.9 && t[0] > 225 && t[1] > 225 && t[2] > 225 && r.height > 300 && r.width > 800; }); const foot = light.length ? light[light.length - 1] : null; return foot ? foot.getBoundingClientRect().top : null; })()''');
      final top = (s is num) ? s.toDouble() : null;
      if (top == null) { result['err'] = 'no footer'; break; }
      final delta = top.round() - (height * 0.5).round();
      if (delta.abs() < 5) break;
      await tab.evaluate(r'''(() => { window.scrollBy(0, ARG); return window.scrollY; })()'''.replaceAll('ARG', delta.toString()));
      await Future.delayed(const Duration(milliseconds: 600));
    }
    result['bottom'] = await tab.evaluate(_bottomJs());
    await tab.evaluate(r'''(() => { document.querySelectorAll('video').forEach(v => v.pause()); return 1; })()''');
    await Future.delayed(const Duration(milliseconds: 300));
    final png = await tab.screenshot();
    File(outPath.replaceAll('.json', '-bottom.png')).writeAsBytesSync(png);
    File(outPath).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('probe seam3 ok -> ' + outPath);
  } finally {
    await client.close();
  }
}