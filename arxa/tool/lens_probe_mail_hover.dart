// lens_probe_mail_hover.dart — footer mail: identity (markup/text/styles) +
// real hover delta. Finds the mail via a[href^="mailto"] else deepest element
// with '@' in direct text. Captures idle + hover computed styles, pseudo
// elements, a 1.4s rAF transition series, and screenshots of both states.
// Usage: dart run tool/lens_probe_mail_hover.dart <url> <outDir> <tag> [w] [h]
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
  let how = 'data-footer-email';
  if (!el) {
    el = [...f.querySelectorAll('a')].find(a => /@/.test(a.textContent || '') && a.getBoundingClientRect().width > 200);
    if (el) how = 'mail-a-200';
  }
  if (!el) {
    const cands = [...f.querySelectorAll('*')].filter(e => !/^(STYLE|SCRIPT|NOSCRIPT|META|LINK|TITLE)$/.test(e.tagName) && [...e.childNodes].some(n => n.nodeType === 3 && /@/.test(n.textContent || '')) && e.getBoundingClientRect().width > 80 && e.getBoundingClientRect().height > 12);
    cands.sort((a, b) => {
      const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect();
      return ra.width * ra.height - rb.width * rb.height;
    });
    el = cands[0] || null; if (el) how = 'text-direct';
  }
  if (!el) return JSON.stringify({ found: false });
  el.setAttribute('data-probe-mail', '1');
  const r = el.getBoundingClientRect();
  const cs = getComputedStyle(el);
  const names = ['color','backgroundColor','fontFamily','fontSize','fontWeight','letterSpacing','lineHeight','textDecorationLine','textDecorationColor','textDecorationThickness','textTransform','cursor','opacity','transitionProperty','transitionDuration','transitionTimingFunction','transform','borderBottomWidth','borderBottomColor','padding','textAlign','whiteSpace','display','alignItems','gap','position'];
  const pick = (s) => { const o = {}; names.forEach(n => o[n] = s[n]); return o; };
  const pseudo = (p) => { const s = getComputedStyle(el, p); return { content: s.content, display: s.display, color: s.color, bg: s.backgroundColor, transform: s.transform, tdur: s.transitionDuration, w: s.width, h: s.height, pos: s.position }; };
  const chain = [];
  let p = el;
  for (let i = 0; i < 3 && p && p !== document.body; i++) {
    chain.push({ tag: p.tagName, cls: ((p.className || '') + '').slice(0, 90), html: (i === 0 ? (p.outerHTML || '') : '').slice(0, 400) });
    p = p.parentElement;
  }
  return JSON.stringify({
    found: true, how, tag: el.tagName, text: (el.textContent || '').trim(),
    rect: { x: r.x, y: r.y, w: r.width, h: r.height },
    styles: pick(cs), before: pseudo('::before'), after: pseudo('::after'), chain
  });
})()
""";
}

String _armJs() {
  return r"""
(() => {
  const el = document.querySelector('[data-probe-mail]');
  if (!el) return 'missing';
  window.__MS = [];
  const t0 = performance.now();
  const names = ['color','textDecorationLine','textDecorationColor','transform','opacity','letterSpacing','backgroundColor'];
  const snap = () => {
    const cs = getComputedStyle(el);
    const o = { t: Math.round(performance.now() - t0) };
    names.forEach(n => o[n] = cs[n]);
    window.__MS.push(o);
    if (performance.now() - t0 < 1400) requestAnimationFrame(snap);
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
    await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': 5.0, 'y': 5.0 });
    await Future.delayed(const Duration(milliseconds: 500));

    final idle = _jd(await tab.evaluate(_findJs()));
    result['idle'] = idle;
    File(outDir + '/' + tag + '-idle.png').writeAsBytesSync(await tab.screenshot());

    if (idle is Map && idle['found'] == true) {
      final rect = idle['rect'] as Map;
      final cx = (rect['x'] as num).toDouble() + (rect['w'] as num).toDouble() / 2;
      final cy = (rect['y'] as num).toDouble() + (rect['h'] as num).toDouble() / 2;
      result['armed'] = await tab.evaluate(_armJs());
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': cx, 'y': cy });
      await Future.delayed(const Duration(milliseconds: 1800));
      final series = _jd(await tab.evaluate(r"(() => JSON.stringify({ n: (window.__MS || []).length, s: (window.__MS || []) }))()"));
      result['series'] = series;
      result['hover'] = _jd(await tab.evaluate(_findJs()));
      File(outDir + '/' + tag + '-hover.png').writeAsBytesSync(await tab.screenshot());
    }

    File(outDir + '/' + tag + '-probe.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('mail probe ok -> ' + outDir + '/' + tag + '-probe.json');
  } finally {
    await client.close();
  }
}
