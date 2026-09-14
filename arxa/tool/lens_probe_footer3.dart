// lens_probe_footer3.dart — final footer unknowns: brand/sticker
// background-image (the orange), click-to-copy tooltip capture on the giant
// email (element watch + styles over time + frames), and a widened
// back-to-top discovery + hover battery.
// Usage: dart run tool/lens_probe_footer3.dart <url> <outDir> <tag>
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

String _imagesJs() {
  return r"""
(() => {
  const f = document.querySelector('footer') || [...document.querySelectorAll('div,section')].find(el => /footer/i.test(String(el.className)) && el.getBoundingClientRect().height > 300);
  const pick = (el) => { const cs = getComputedStyle(el); return { bg: cs.backgroundColor, bgi: cs.backgroundImage }; };
  const brand = [...f.querySelectorAll('div')].find(d => getComputedStyle(d).borderRadius === '24px' && d.getBoundingClientRect().width < 500 && d.getBoundingClientRect().width > 300);
  let sticker = null;
  [...f.querySelectorAll('*')].forEach(el => { if (!sticker) { const cs = getComputedStyle(el); if (cs.position === 'absolute' && cs.transform !== 'none' && el.getBoundingClientRect().width > 20 && el.getBoundingClientRect().width < 160) sticker = el; } });
  return JSON.stringify({ footer: pick(f), brand: brand ? pick(brand) : null, sticker: sticker ? pick(sticker) : null });
})()
""";
}

String _bttFindJs() {
  return r"""
(() => {
  const out = [];
  [...document.querySelectorAll('button, a, div, span')].forEach(el => {
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    if ((cs.position === 'fixed' || cs.position === 'sticky') && r.width >= 30 && r.width <= 110 && r.y > window.innerHeight - 160 && r.x > window.innerWidth - 160) {
      out.push({ tag: el.tagName.toLowerCase(), cls: String(el.className || '').slice(0, 50), x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), bg: cs.backgroundColor, sh: cs.boxShadow, trans: cs.transitionProperty + '|' + cs.transitionDuration + '|' + cs.transitionTimingFunction, txt: (el.textContent || '').trim().slice(0, 6) });
    }
  });
  return JSON.stringify(out);
})()
""";
}

String _tooltipWatchJs() {
  return r"""
(() => {
  const f = document.querySelector('footer') || document.body;
  const before = new Set([...document.querySelectorAll('body *')]);
  window.__TT = [];
  const t0 = performance.now();
  const snap = () => {
    [...document.querySelectorAll('body *')].forEach(el => {
      if (before.has(el)) return;
      const cs = getComputedStyle(el);
      const r = el.getBoundingClientRect();
      if (r.width > 0) {
        window.__TT.push({ t: Math.round(performance.now() - t0), tag: el.tagName.toLowerCase(), txt: (el.textContent || '').trim().slice(0, 40), x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height * 10) / 10, bg: cs.backgroundColor, c: cs.color, rad: cs.borderRadius, fs: cs.fontSize, fw: cs.fontWeight, op: cs.opacity, tr: cs.transform, scale: cs.scale, pos: cs.position, z: cs.zIndex, sh: cs.boxShadow });
      }
    });
    if (performance.now() - t0 < 1500) requestAnimationFrame(snap);
  };
  requestAnimationFrame(snap);
  const target = [...f.querySelectorAll('*')].find(el => {
    const r = el.getBoundingClientRect();
    return /@/.test(el.textContent || '') && r.width > 400 && el.children.length <= 3 && !el.contains(f.querySelector('[class*="links"], [class*="meta"]'));
  }) || f;
  const r = target.getBoundingClientRect();
  target.click();
  return { clicked: true, tag: target.tagName.toLowerCase(), cls: String(target.className || '').slice(0, 40), x: Math.round(r.x), y: Math.round(r.y) };
})()
""";
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final outDir = args.length > 1 ? args[1] : '/tmp/arxa-compare/pf';
  final tag = args.length > 2 ? args[2] : 'f3';
  final result = <String, dynamic>{ 'url': url, 'tag': tag };
  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1713, 1098);
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
    await Future.delayed(const Duration(milliseconds: 1200));

    final img = await tab.evaluate(_imagesJs());
    result['images'] = jsonDecode(img is String ? img : jsonEncode(img));

    final btt = await tab.evaluate(_bttFindJs());
    final bttList = jsonDecode(btt is String ? btt : jsonEncode(btt)) as List;
    result['bttCandidates'] = bttList;
    if (bttList.isNotEmpty) {
      final b0 = bttList[0] as Map<String, dynamic>;
      final bx = (b0['x'] as num).toDouble() + ((b0['w'] as num).toDouble() / 2);
      final by = (b0['y'] as num).toDouble() + ((b0['w'] as num).toDouble() / 2);
      await tab.evaluate(r"""
(() => {
  const el = [...document.querySelectorAll('button, a, div, span')].find(el => {
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return (cs.position === 'fixed' || cs.position === 'sticky') && r.width >= 30 && r.width <= 110 && r.y > window.innerHeight - 160 && r.x > window.innerWidth - 160;
  });
  if (!el) return 'missing';
  el.setAttribute('data-probe-btt', '1');
  window.__HA = [];
  window.__HAN = null;
  const t0 = performance.now();
  const snap = () => {
    const cs = getComputedStyle(el);
    window.__HA.push({ t: Math.round(performance.now() - t0), c: cs.color, bg: cs.backgroundColor, tr: cs.transform, op: cs.opacity, sh: cs.boxShadow });
    if (performance.now() - t0 < 900) requestAnimationFrame(snap);
  };
  requestAnimationFrame(snap);
  setTimeout(() => { window.__HAN = (el.getAnimations ? el.getAnimations({ subtree: true }) : []).map(a => { const ct = a.effect ? a.effect.getComputedTiming() : null; return { cls: a.constructor.name, prop: a.transitionProperty || null, dur: ct ? ct.duration : null, ease: ct ? ct.easing : null }; }); }, 80);
  return 'armed';
})()
""");
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': bx, 'y': by });
      await Future.delayed(const Duration(milliseconds: 800));
      final col = await tab.evaluate(r"(() => JSON.stringify({ anims: window.__HAN || null, samples: window.__HA || null }))()");
      result['bttHover'] = jsonDecode(col is String ? col : jsonEncode(col));
    }

    await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': 5, 'y': 5 });
    await Future.delayed(const Duration(milliseconds: 300));
    final click = await tab.evaluate(_tooltipWatchJs());
    result['copyClick'] = click is Map ? click : jsonEncode(click);
    await Future.delayed(const Duration(milliseconds: 300));
    File(outDir + '/' + tag + '-copy-300.png').writeAsBytesSync(await tab.screenshot());
    await Future.delayed(const Duration(milliseconds: 1300));
    result['tooltip'] = { 'found': true };
    final tt = await tab.evaluate(r"(() => JSON.stringify(window.__TT || []))()");
    result['tooltipEvents'] = jsonDecode(tt is String ? tt : jsonEncode(tt));
    File(outDir + '/' + tag + '-footer3.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('footer3 ok -> ' + outDir + '/' + tag + '-footer3.json');
  } finally {
    await client.close();
  }
}

