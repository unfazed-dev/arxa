// lens_probe_footer2.dart — footer deep details: full anchor list, pseudo
// element styles (brand card / sticker orange), email svg fill + ancestor
// anchor, the footer <style> tag full text (copyTooltipIn keyframes), a
// click-to-copy probe on the email (watching for tooltip elements), brand
// card hover, and the floating back-to-top hover inventory.
// Usage: dart run tool/lens_probe_footer2.dart <url> <outDir> <tag> [w] [h]
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

String _detailsJs() {
  return r"""
(() => {
  const f = document.querySelector('footer') || [...document.querySelectorAll('div,section')].find(el => /footer/i.test(String(el.className)) && el.getBoundingClientRect().height > 300);
  if (!f) return JSON.stringify({ error: 'no-footer' });
  const anchors = [...f.querySelectorAll('a')].filter(a => { const r = a.getBoundingClientRect(); return r.width > 0 && r.height > 0; }).map(a => {
    const cs = getComputedStyle(a);
    const r = a.getBoundingClientRect();
    return { txt: (a.textContent || '').trim().slice(0, 40), fs: cs.fontSize, fw: cs.fontWeight, w: Math.round(r.width), h: Math.round(r.height * 10) / 10, x: Math.round(r.x), y: Math.round(r.y), td: cs.textDecorationLine, c: cs.color, trans: cs.transitionProperty + '|' + cs.transitionDuration + '|' + cs.transitionTimingFunction };
  });
  const pseudo = (el, name) => {
    if (!el) return null;
    const cs = getComputedStyle(el, name);
    return { content: cs.content, bg: cs.backgroundColor, rad: cs.borderRadius, pos: cs.position, inset: cs.inset, w: cs.width, h: cs.height };
  };
  const brand = f.querySelector('[class*="brand"], [class*="Brand"]') || [...f.querySelectorAll('div')].find(d => { const cs = getComputedStyle(d); return cs.borderRadius === '24px' && d.getBoundingClientRect().width < 500 && d.getBoundingClientRect().width > 300; });
  let sticker = null;
  [...f.querySelectorAll('*')].forEach(el => {
    if (sticker) return;
    const cs = getComputedStyle(el);
    if (cs.position === 'absolute' && cs.transform !== 'none' && el.getBoundingClientRect().width > 20 && el.getBoundingClientRect().width < 160) sticker = el;
  });
  const textEl = [...f.querySelectorAll('text')].find(t => /@/.test(t.textContent || ''));
  let emailAnchor = null, fill = null, fillColor = null;
  if (textEl) {
    fill = getComputedStyle(textEl).fill;
    fillColor = getComputedStyle(textEl).color;
    emailAnchor = textEl.closest('a');
  }
  const styleTags = [...f.querySelectorAll('style')].map(s => s.textContent || '').join('\n---\n');
  let btt = null;
  [...document.querySelectorAll('button, a, div')].forEach(el => {
    if (btt) return;
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    if (cs.position === 'fixed' && r.width > 36 && r.width < 90 && r.y > window.innerHeight - 140 && r.x > window.innerWidth - 140 && (el.textContent || '').trim().length < 4) btt = { tag: el.tagName.toLowerCase(), cls: String(el.cls || el.className || '').slice(0, 40), x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), bg: cs.backgroundColor, sh: cs.boxShadow, trans: cs.transitionProperty + '|' + cs.transitionDuration + '|' + cs.transitionTimingFunction };
  });
  return JSON.stringify({ anchors: anchors, brandPseudo: { before: pseudo(brand, '::before'), after: pseudo(brand, '::after'), bg: brand ? getComputedStyle(brand).backgroundColor : null }, stickerPseudo: { before: pseudo(sticker, '::before'), after: pseudo(sticker, '::after'), bg: sticker ? getComputedStyle(sticker).backgroundColor : null }, email: { fill: fill, color: fillColor, anchorTag: emailAnchor ? emailAnchor.tagName.toLowerCase() : null, anchorCls: emailAnchor ? String(emailAnchor.className) : null, anchorHref: emailAnchor ? emailAnchor.getAttribute('href') : null }, styleText: styleTags.slice(0, 2000), btt: btt });
})()
""";
}

String _armJs(String selector) {
  return r"""
(() => {
  const el = document.querySelector('SEL');
  if (!el) return 'missing';
  window.__HA = [];
  window.__HAN = null;
  const t0 = performance.now();
  const snap = () => {
    const cs = getComputedStyle(el);
    window.__HA.push({ t: Math.round(performance.now() - t0), c: cs.color, bg: cs.backgroundColor, tr: cs.transform, op: cs.opacity });
    if (performance.now() - t0 < 900) requestAnimationFrame(snap);
  };
  requestAnimationFrame(snap);
  setTimeout(() => {
    window.__HAN = (el.getAnimations ? el.getAnimations({ subtree: true }) : []).map(a => {
      const ct = a.effect ? a.effect.getComputedTiming() : null;
      return { cls: a.constructor.name, prop: a.transitionProperty || (a.effect && a.effect.getKeyframes ? 'kf' : null), pseudo: a.effect && a.effect.pseudoElement ? a.effect.pseudoElement : null, dur: ct ? ct.duration : null, ease: ct ? ct.easing : null };
    });
  }, 80);
  return 'armed';
})()
""".replaceAll('SEL', selector);
}

String _collectJs() {
  return r"""
(() => JSON.stringify({ anims: window.__HAN || null, samples: window.__HA || null }))()
""";
}

String _tooltipWatchJs() {
  return r"""
(() => {
  const f = document.querySelector('footer') || document.body;
  const seen = new Map();
  const t0 = performance.now();
  window.__TT = [];
  const snap = () => {
    [...document.querySelectorAll('body *')].forEach(el => {
      if (seen.has(el)) return;
      const cs = getComputedStyle(el);
      if ((cs.position === 'fixed' || cs.position === 'absolute') && el.getBoundingClientRect().width > 0 && el.getBoundingClientRect().width < 400 && (el.textContent || '').trim().length > 0 && (el.textContent || '').trim().length < 60 && el.children.length <= 2) {
        const r = el.getBoundingClientRect();
        if (r.y > window.innerHeight - 400) {
          seen.set(el, 1);
          window.__TT.push({ t: Math.round(performance.now() - t0), txt: (el.textContent || '').trim().slice(0, 40), x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height * 10) / 10, bg: cs.backgroundColor, c: cs.color, rad: cs.borderRadius, fs: cs.fontSize, op: cs.opacity, tr: cs.transform, scale: cs.scale });
        }
      }
    });
    if (performance.now() - t0 < 1400) requestAnimationFrame(snap);
  };
  requestAnimationFrame(snap);
  const a = [...f.querySelectorAll('a')].find(a => /@/.test(a.textContent || '') && a.getBoundingClientRect().width > 200);
  if (a) { const r = a.getBoundingClientRect(); a.click(); return { clicked: true, x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) }; }
  return { clicked: false };
})()
""";
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final outDir = args.length > 1 ? args[1] : '/tmp/arxa-compare/pf';
  final tag = args.length > 2 ? args[2] : 'f2';
  final w = args.length > 3 ? int.parse(args[3]) : 1713;
  final h = args.length > 4 ? int.parse(args[4]) : 1098;
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
    await Future.delayed(const Duration(milliseconds: 1200));

    final det = await tab.evaluate(_detailsJs());
    final detS = det is String ? det : jsonEncode(det);
    result['details'] = jsonDecode(detS);
    final d = result['details'] as Map<String, dynamic>;

    // brand card hover (its ::before carries the orange on the reference)
    await tab.evaluate(_armJs('[class*="brand"], [class*="Brand"]'));
    final bc = (d['brandPseudo'] != null);
    await tab.evaluate(r"""
(() => { const f = document.querySelector('footer'); const el = f.querySelector('[class*="brand"], [class*="Brand"]') || [...f.querySelectorAll('div')].find(d => getComputedStyle(d).borderRadius === '24px' && d.getBoundingClientRect().width < 500); if (!el) return 0; const r = el.getBoundingClientRect(); el.setAttribute('data-probe-b', '1'); return 1; })()
""");
    final c1 = await tab.evaluate(r"""
(() => { const el = document.querySelector('[data-probe-b]'); if (!el) return null; const r = el.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; })()
""");
    if (c1 is List && c1.length == 2) {
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': (c1[0] as num).toDouble(), 'y': (c1[1] as num).toDouble() });
      await Future.delayed(const Duration(milliseconds: 700));
      final col = await tab.evaluate(_collectJs());
      result['brandHover'] = jsonDecode(col is String ? col : jsonEncode(col));
    }

    // back-to-top hover
    final btt = d['btt'] as Map<String, dynamic>?;
    if (btt != null) {
      final bx = (btt['x'] as num).toDouble() + ((btt['w'] as num).toDouble() / 2);
      final by = (btt['y'] as num).toDouble() + ((btt['w'] as num).toDouble() / 2);
      await tab.evaluate(_armJs("footer, body").replaceAll('SEL-PLACEHOLDER', ''));
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': 5, 'y': 5 });
      await Future.delayed(const Duration(milliseconds: 200));
      // arm on the discovered back-to-top via coordinate sample
      await tab.evaluate(r"""
(() => {
  const el = [...document.querySelectorAll('button, a, div')].find(el => {
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return cs.position === 'fixed' && r.width > 36 && r.width < 90 && r.y > window.innerHeight - 140 && r.x > window.innerWidth - 140 && (el.textContent || '').trim().length < 4;
  });
  if (!el) return 'missing';
  el.setAttribute('data-probe-t', '1');
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
      await Future.delayed(const Duration(milliseconds: 750));
      final col2 = await tab.evaluate(_collectJs());
      result['bttHover'] = jsonDecode(col2 is String ? col2 : jsonEncode(col2));
    }

    // click-to-copy tooltip watch on the email
    await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': 5, 'y': 5 });
    await Future.delayed(const Duration(milliseconds: 300));
    final click = await tab.evaluate(_tooltipWatchJs());
    result['copyClick'] = click is Map ? click : jsonEncode(click);
    await Future.delayed(const Duration(milliseconds: 350));
    File(outDir + '/' + tag + '-copy-350.png').writeAsBytesSync(await tab.screenshot());
    await Future.delayed(const Duration(milliseconds: 900));
    final ttDone = await tab.evaluate(r"(() => JSON.stringify({ n: (window.__TT || []).length, found: window.__TT || null }))()");
    result['tooltip'] = jsonDecode(ttDone is String ? ttDone : jsonEncode(ttDone));

    File(outDir + '/' + tag + '-footer2.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('footer2 ok -> ' + outDir + '/' + tag + '-footer2.json');
  } finally {
    await client.close();
  }
}

