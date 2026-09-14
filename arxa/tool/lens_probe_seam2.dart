// lens_probe_seam2.dart — corner-radius ground truth + real-wheel seam burst.
// Part A: elementsFromPoint coverage scan of #clientstories' top corners
// (right/left columns at 2px inset, dy 0..48 step 2; row sweep at dy=1)
// — the 0/1 patterns give each site's effective corner radius. Plus the
// white-peek scan and a screenshot at the reported composition.
// Part B: trusted CDP mouseWheel drive across the seam (down then up),
// screenshotting every notch with a numeric nav-pill sample per frame —
// catches wheel-driven states programmatic scrolling never shows.
// Usage: dart run tool/lens_probe_seam2.dart <url> [w] [h] [outJson]
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

String _cornerJs() {
  return r'''
(() => {
  const s = document.getElementById('clientstories');
  if (!s) return JSON.stringify({ err: 'no section' });
  const top = s.getBoundingClientRect().top;
  const W = window.innerWidth;
  const covered = (x, y) => document.elementsFromPoint(x, y).some(e => e === s || s.contains(e));
  const right = [], left = [], rowR = [], rowL = [];
  for (let dy = 0; dy <= 48; dy += 2) { right.push(covered(W - 2, top + dy) ? 1 : 0); left.push(covered(2, top + dy) ? 1 : 0); }
  for (let d = 0; d <= 48; d += 2) { rowR.push(covered(W - d, top + 1) ? 1 : 0); rowL.push(covered(d, top + 1) ? 1 : 0); }
  const shell = s.parentElement;
  const ss = getComputedStyle(shell);
  return JSON.stringify({ top: Math.round(top), vw: W, right: right.join(''), left: left.join(''), rowR: rowR.join(''), rowL: rowL.join(''), shellCls: String(shell.className).slice(0, 60), shellRadius: ss.borderRadius, shellOverflow: ss.overflow, secRadius: getComputedStyle(s).borderRadius });
})()
''';
}

String _scanJs() {
  return r'''
(() => {
  const W = window.innerWidth, H = window.innerHeight;
  const parseC = (s) => { const t = s.replace('rgba(', '').replace('rgb(', '').replace(')', ''); const p = t.split(',').map(x => parseFloat(x)); return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 }; };
  const visOf = (el) => { const b0 = el.getBoundingClientRect(); const box = { top: b0.top, left: b0.left, right: b0.right, bottom: b0.bottom }; let p = el.parentElement; while (p) { const ps = getComputedStyle(p); if (ps.overflowX !== 'visible' || ps.overflowY !== 'visible') { const pr = p.getBoundingClientRect(); box.top = Math.max(box.top, pr.top); box.left = Math.max(box.left, pr.left); box.bottom = Math.min(box.bottom, pr.bottom); box.right = Math.min(box.right, pr.right); } p = p.parentElement; } return box; };
  const clsOf = (e) => { const c = e.className; return String(c && c.baseVal !== undefined ? c.baseVal : c).slice(0, 70); };
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
    hits.push({ tag: el.tagName, cls: clsOf(el), rect: { x: Math.round(b.x), y: Math.round(b.y), w: Math.round(b.width), h: Math.round(b.height) }, vis: { x: Math.round(il), y: Math.round(it), w: Math.round(iw), h: Math.round(ih) }, peekTop: b.top < -1, peekRight: b.right > W + 1, peekLeft: b.left < -1 });
  });
  hits.sort((a, b) => (b.vis.w * b.vis.h) - (a.vis.w * a.vis.h));
  return JSON.stringify(hits.slice(0, 12));
})()
''';
}

String _navJs() {
  return r'''
(() => {
  let n = document.querySelector('.site-nav');
  if (!n) n = [...document.querySelectorAll('*')].find(d => { const s = getComputedStyle(d); return s.position === 'fixed' && s.top === '16px'; });
  if (!n) return JSON.stringify({ nav: null });
  const cs = getComputedStyle(n);
  const pill = n.querySelector('.nav-pill') || n.firstElementChild;
  const pr = pill ? pill.getBoundingClientRect() : n.getBoundingClientRect();
  return JSON.stringify({ transform: cs.transform, opacity: cs.opacity, vis: cs.visibility, pillX: Math.round(pr.x), pillY: Math.round(pr.y), pillW: Math.round(pr.width), pillH: Math.round(pr.height) });
})()
''';
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final width = args.length > 1 ? int.parse(args[1]) : 1713;
  final height = args.length > 2 ? int.parse(args[2]) : 1098;
  final outPath = args.length > 3 ? args[3] : '/tmp/arxa-compare/seam/probe2.json';
  final result = <String, dynamic>{ 'url': url, 'viewport': '$width x $height' };
  final client = await LensDaemon.acquire();
  Future<void> shot(String name, tab) async {
    await tab.evaluate(r'''(() => { document.querySelectorAll('video').forEach(v => v.pause()); return 1; })()''');
    await Future.delayed(const Duration(milliseconds: 250));
    final png = await tab.screenshot();
    final p = outPath.replaceAll('.json', '-') + name + '.png';
    File(p).writeAsBytesSync(png);
    return;
  }
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
    // converge: #clientstories top at 0.496 vh (the reported composition)
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
    result['corner'] = await tab.evaluate(_cornerJs());
    result['scan'] = await tab.evaluate(_scanJs());
    await shot('seam', tab);
    // Part B: trusted wheel burst — start with the seam just below the fold
    for (int i = 0; i < 6; i++) {
      final s = await tab.evaluate(r'''(() => { const s = document.getElementById('clientstories'); return s.getBoundingClientRect().top; })()''');
      final top = (s is num) ? s.toDouble() : height * 2;
      final delta = top.round() - (height * 0.95).round();
      if (delta.abs() < 5) break;
      await tab.evaluate(r'''(() => { window.scrollBy(0, ARG); return window.scrollY; })()'''.replaceAll('ARG', delta.toString()));
      await Future.delayed(const Duration(milliseconds: 500));
    }
    final frames = <Map<String, dynamic>>[];
    for (int i = 0; i < 10; i++) {
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseWheel', 'x': (width / 2).round(), 'y': (height / 2).round(), 'deltaX': 0, 'deltaY': 320 });
      await Future.delayed(const Duration(milliseconds: 260));
      final st = await tab.evaluate(r'''(() => { const s = document.getElementById('clientstories'); return Math.round(s.getBoundingClientRect().top); })()''');
      final nav = await tab.evaluate(_navJs());
      frames.add({ 'dir': 'down', 'i': i + 1, 'seamTop': st, 'nav': nav });
      await shot('down-' + (i + 1).toString(), tab);
      if ((st is num) && st < height * 0.05) break;
    }
    for (int i = 0; i < 10; i++) {
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseWheel', 'x': (width / 2).round(), 'y': (height / 2).round(), 'deltaX': 0, 'deltaY': -320 });
      await Future.delayed(const Duration(milliseconds: 260));
      final st = await tab.evaluate(r'''(() => { const s = document.getElementById('clientstories'); return Math.round(s.getBoundingClientRect().top); })()''');
      final nav = await tab.evaluate(_navJs());
      frames.add({ 'dir': 'up', 'i': i + 1, 'seamTop': st, 'nav': nav });
      await shot('up-' + (i + 1).toString(), tab);
      if ((st is num) && st > height * 1.4) break;
    }
    result['frames'] = frames;
    File(outPath).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('probe seam2 ok -> ' + outPath);
  } finally {
    await client.close();
  }
}