// lens_probe_seam.dart — the how-it-works → stories seam check. Places
// #clientstories top at 49.6% of the viewport (the composition from the
// field report), then lists every painted near-white element whose visible
// box intersects the viewport, flagged with off-viewport peek flags, plus
// elementsFromPoint chains at the two reported shape positions. Run on
// both sites; the reference decides which peeks are legal.
// Usage: dart run tool/lens_probe_seam.dart <url> [width] [height] [outJson]
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

String _scanJs() {
  return r'''
(() => {
  const W = window.innerWidth, H = window.innerHeight;
  const parseC = (s) => { const t = s.replace('rgba(', '').replace('rgb(', '').replace(')', ''); const p = t.split(',').map(x => parseFloat(x)); return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 }; };
  const visOf = (el) => { const b0 = el.getBoundingClientRect(); const box = { top: b0.top, left: b0.left, right: b0.right, bottom: b0.bottom }; let p = el.parentElement; while (p) { const ps = getComputedStyle(p); if (ps.overflowX !== 'visible' || ps.overflowY !== 'visible') { const pr = p.getBoundingClientRect(); box.top = Math.max(box.top, pr.top); box.left = Math.max(box.left, pr.left); box.bottom = Math.min(box.bottom, pr.bottom); box.right = Math.min(box.right, pr.right); } p = p.parentElement; } return box; };
  const clsOf = (e) => { const c = e.className; return String(c && c.baseVal !== undefined ? c.baseVal : c).slice(0, 90); };
  const hits = [];
  document.querySelectorAll('body *').forEach(el => {
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility !== 'visible' || parseFloat(cs.opacity) < 0.05) return;
    const c = parseC(cs.backgroundColor);
    if (c.a < 0.05) return;
    if (!(c.r > 225 && c.g > 225 && c.b > 225)) return;
    const b = el.getBoundingClientRect();
    if (b.width < 8 || b.height < 8) return;
    const v = visOf(el);
    const il = Math.max(v.left, 0), it = Math.max(v.top, 0), ir = Math.min(v.right, W), ib = Math.min(v.bottom, H);
    const iw = ir - il, ih = ib - it;
    if (iw < 6 || ih < 6) return;
    hits.push({ tag: el.tagName, cls: clsOf(el), bg: cs.backgroundColor, pos: cs.position, z: cs.zIndex, radius: cs.borderRadius, rect: { x: Math.round(b.x), y: Math.round(b.y), w: Math.round(b.width), h: Math.round(b.height) }, vis: { x: Math.round(il), y: Math.round(it), w: Math.round(iw), h: Math.round(ih) }, peekTop: b.top < -1, peekRight: b.right > W + 1, peekLeft: b.left < -1, peekBottom: b.bottom > H + 1 });
  });
  hits.sort((a, b) => (b.vis.w * b.vis.h) - (a.vis.w * a.vis.h));
  const chainAt = (x, y) => document.elementsFromPoint(x, y).slice(0, 5).map(e => { const cs = getComputedStyle(e); return { tag: e.tagName, cls: clsOf(e), bg: cs.backgroundColor, pos: cs.position, z: cs.zIndex }; });
  return JSON.stringify({ vw: W, vh: H, hits: hits.slice(0, 30), probeTop: chainAt(Math.round(W * 0.415), 4), probeRight: chainAt(W - 8, Math.round(H * 0.5)) });
})()
''';
}

String _hiwJs() {
  return r'''
(() => {
  const st = document.getElementById('clientstories');
  const prev = st.previousElementSibling;
  const out = { prevTag: prev ? prev.tagName : null, prevCls: prev ? String(prev.className).slice(0, 70) : null, prevH: prev ? prev.offsetHeight : null, prevBg: prev ? getComputedStyle(prev).backgroundColor : null };
  const sticky = prev ? [...prev.querySelectorAll('*')].find(d => getComputedStyle(d).position === 'sticky') : null;
  if (sticky) {
    const cs = getComputedStyle(sticky);
    const r = sticky.getBoundingClientRect();
    out.sticky = { cls: String(sticky.className).slice(0, 70), y: Math.round(r.y), h: Math.round(r.height), bg: cs.backgroundColor, transform: cs.transform.slice(0, 80), opacity: cs.opacity };
  }
  return JSON.stringify(out);
})()
''';
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final width = args.length > 1 ? int.parse(args[1]) : 1713;
  final height = args.length > 2 ? int.parse(args[2]) : 1098;
  final outPath = args.length > 3 ? args[3] : '/tmp/arxa-compare/seam/probe-seam.json';
  final result = <String, dynamic>{ 'url': url, 'viewport': '$width x $height' };
  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: 700);
    final w = Stopwatch()..start();
    var revealed = false;
    while (w.elapsedMilliseconds < 30000) {
      final ok = await tab.evaluate(_revealJs());
      if (ok == true) { revealed = true; break; }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    result['revealed'] = revealed;
    await Future.delayed(const Duration(milliseconds: 800));
    await tab.evaluate(r'''(() => { const btn = [...document.querySelectorAll('button')].find(b => /^(accept)$/i.test((b.textContent || '').trim())); if (btn) btn.click(); return !!btn; })()''');
    await Future.delayed(const Duration(milliseconds: 400));
    final target = (height * 0.496).round();
    for (int i = 0; i < 6; i++) {
      final s = await tab.evaluate(r'''(() => { const s = document.getElementById('clientstories'); return s ? s.getBoundingClientRect().top : null; })()''');
      final top = (s is num) ? s.toDouble() : null;
      if (top == null) { result['err'] = 'no clientstories'; break; }
      final delta = top.round() - target;
      if (delta.abs() < 5) break;
      await tab.evaluate(r'''(() => { window.scrollBy(0, ARG); return window.scrollY; })()'''.replaceAll('ARG', delta.toString()));
      await Future.delayed(const Duration(milliseconds: 650));
    }
    await Future.delayed(const Duration(milliseconds: 500));
    result['seamTop'] = await tab.evaluate(r'''(() => { const s = document.getElementById('clientstories'); return Math.round(s.getBoundingClientRect().top); })()''');
    result['scrollY'] = await tab.evaluate(r'''window.scrollY''');
    result['hiw'] = await tab.evaluate(_hiwJs());
    result['scan'] = await tab.evaluate(_scanJs());
    await tab.evaluate(r'''(() => { document.querySelectorAll('video').forEach(v => v.pause()); return document.querySelectorAll('video').length; })()''');
    await Future.delayed(const Duration(milliseconds: 300));
    final png = await tab.screenshot();
    final shotPath = outPath.replaceAll('.json', '-seam.png');
    File(shotPath).writeAsBytesSync(png);
    result['shot'] = shotPath;
    File(outPath).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('probe seam ok -> ' + outPath);
  } finally {
    await client.close();
  }
}