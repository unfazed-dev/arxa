// lens_probe_footer.dart — footer parity capture: entrance sampling while
// scrolling to the bottom, a computed-style tree dump, and a real-mouse
// hover battery (Input.dispatchMouseEvent mouseMoved) over the discovered
// targets (first nav link, Book-a-call pill, sticker, giant email) with a
// rAF sampler + getAnimations inventory per target, hover-in AND out.
// Usage: dart run tool/lens_probe_footer.dart <url> <outDir> <tag> [w] [h]
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

String _footerElJs() {
  return r"""
(document.querySelector('footer') || [...document.querySelectorAll('div,section')].find(el => /footer/i.test(String(el.className)) && el.getBoundingClientRect().height > 300))
""";
}

String _entranceJs() {
  return r"""
(() => {
  const f = FOOTER;
  if (!f) return 'no-footer';
  const els = [f, ...f.querySelectorAll(':scope > *')];
  window.__FS = [];
  const t0 = performance.now();
  const snap = () => {
    const row = { t: Math.round(performance.now() - t0) };
    els.forEach((el, i) => {
      const cs = getComputedStyle(el);
      row['o' + i] = cs.opacity;
      row['tr' + i] = cs.transform;
    });
    window.__FS.push(row);
    if (performance.now() - t0 < 3800) requestAnimationFrame(snap);
  };
  requestAnimationFrame(snap);
  window.scrollTo(0, document.body.scrollHeight);
  return els.length;
})()
""".replaceAll('FOOTER', '(document.querySelector("footer") || [...document.querySelectorAll("div,section")].find(el => /footer/i.test(String(el.className)) && el.getBoundingClientRect().height > 300))');
}

String _collectEntranceJs() {
  return r"""
(() => JSON.stringify({ n: (window.__FS || []).length, samples: window.__FS || null }))()
""";
}

String _treeJs() {
  return r"""
(() => {
  const f = FOOTER;
  if (!f) return 'null';
  const clsOf = (el) => (el.className ? (typeof el.className === 'string' ? el.className : (el.className.baseVal || '')) : '');
  const tree = (el, d) => {
    if (!el || d > 5) return null;
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    const node = {
      tag: el.tagName.toLowerCase(), cls: clsOf(el),
      x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height * 10) / 10,
      bg: cs.backgroundColor, rad: cs.borderRadius, pad: cs.padding,
      color: cs.color, fs: cs.fontSize, fw: cs.fontWeight, lh: cs.lineHeight, ls: cs.letterSpacing,
      td: cs.textDecorationLine, tr: cs.transform, sh: cs.boxShadow,
      trans: cs.transitionProperty + ' | ' + cs.transitionDuration + ' | ' + cs.transitionTimingFunction,
      txt: (el.children.length === 0 ? (el.textContent || '').trim().slice(0, 48) : ''),
      kids: [...el.children].map(c => tree(c, d + 1))
    };
    return node;
  };
  return JSON.stringify(tree(f, 0));
})()
""".replaceAll('FOOTER', '(document.querySelector("footer") || [...document.querySelectorAll("div,section")].find(el => /footer/i.test(String(el.className)) && el.getBoundingClientRect().height > 300))');
}

String _discoverJs() {
  return r"""
(() => {
  const f = FOOTER;
  if (!f) return 'null';
  const anchors = [...f.querySelectorAll('a')].filter(a => { const r = a.getBoundingClientRect(); return r.width > 0 && r.height > 0; });
  let email = null, pill = null, maxFs = 0;
  anchors.forEach(a => { const fs = parseFloat(getComputedStyle(a).fontSize); if (fs > maxFs) { maxFs = fs; email = a; } });
  anchors.forEach(a => { if (a !== email && /book/i.test(a.textContent || '')) { if (!pill) pill = a; } });
  const links = anchors.filter(a => a !== email && a !== pill && parseFloat(getComputedStyle(a).fontSize) < 40);
  const link = links.length ? links[0] : null;
  let sticker = null;
  [...f.querySelectorAll('*')].forEach(el => {
    if (sticker) return;
    const cs = getComputedStyle(el);
    if (cs.position === 'absolute' && cs.transform !== 'none' && el.getBoundingClientRect().width < 160 && el.getBoundingClientRect().width > 20) sticker = el;
  });
  const c = (el) => { if (!el) return null; const r = el.getBoundingClientRect(); return { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) }; };
  const tag = (el, name) => { if (el) el.setAttribute('data-probe', name); };
  tag(email, 'email'); tag(pill, 'pill'); tag(link, 'link'); tag(sticker, 'sticker');
  return JSON.stringify({ email: c(email), pill: c(pill), link: c(link), sticker: c(sticker), nLinks: links.length });
})()
""".replaceAll('FOOTER', '(document.querySelector("footer") || [...document.querySelectorAll("div,section")].find(el => /footer/i.test(String(el.className)) && el.getBoundingClientRect().height > 300))');
}

String _armHoverJs(String name) {
  return r"""
(() => {
  const el = document.querySelector('[data-probe="NAME"]');
  if (!el) return 'missing';
  window.__HA = [];
  window.__HAN = null;
  const t0 = performance.now();
  const snap = () => {
    const cs = getComputedStyle(el);
    window.__HA.push({ t: Math.round(performance.now() - t0), c: cs.color, bg: cs.backgroundColor, tr: cs.transform, op: cs.opacity, ls: cs.letterSpacing, td: cs.textDecorationLine, sh: cs.boxShadow, fs: cs.fontSize });
    if (performance.now() - t0 < 900) requestAnimationFrame(snap);
  };
  requestAnimationFrame(snap);
  setTimeout(() => {
    window.__HAN = (el.getAnimations ? el.getAnimations({ subtree: true }) : []).map(a => {
      const ct = a.effect ? a.effect.getComputedTiming() : null;
      return { cls: a.constructor.name, prop: a.transitionProperty || null, dur: ct ? ct.duration : null, ease: ct ? ct.easing : null };
    });
  }, 80);
  return 'armed';
})()
""".replaceAll('NAME', name);
}

String _collectHoverJs() {
  return r"""
(() => JSON.stringify({ anims: window.__HAN || null, samples: window.__HA || null }))()
""";
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final outDir = args.length > 1 ? args[1] : '/tmp/arxa-compare/pf';
  final tag = args.length > 2 ? args[2] : 'footer';
  final w = args.length > 3 ? int.parse(args[3]) : 1713;
  final h = args.length > 4 ? int.parse(args[4]) : 1098;
  final result = <String, dynamic>{ 'url': url, 'tag': tag, 'w': w, 'h': h };
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
    await Future.delayed(const Duration(milliseconds: 800));
    await tab.evaluate(_acceptJs());
    await Future.delayed(const Duration(milliseconds: 400));

    final els = await tab.evaluate(_entranceJs());
    result['entranceEls'] = els is String ? els : jsonEncode(els);
    await Future.delayed(const Duration(milliseconds: 4000));
    final ent = await tab.evaluate(_collectEntranceJs());
    result['entrance'] = jsonDecode(ent is String ? ent : jsonEncode(ent));
    File(outDir + '/' + tag + '-footer.png').writeAsBytesSync(await tab.screenshot());

    final tree = await tab.evaluate(_treeJs());
    final treeS = tree is String ? tree : jsonEncode(tree);
    result['tree'] = treeS == 'null' ? null : jsonDecode(treeS);

    final disc = await tab.evaluate(_discoverJs());
    final discS = disc is String ? disc : jsonEncode(disc);
    result['targets'] = jsonDecode(discS);
    final t = result['targets'] as Map<String, dynamic>;

    final hoverOut = <String, dynamic>{};
    for (final name in ['link', 'pill', 'sticker', 'email']) {
      final c = t[name] as Map<String, dynamic>?;
      if (c == null) { hoverOut[name] = 'absent'; continue; }
      await tab.evaluate(_armHoverJs(name));
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': (c['x'] as num).toDouble(), 'y': (c['y'] as num).toDouble() });
      await Future.delayed(const Duration(milliseconds: 380));
      File(outDir + '/' + tag + '-hover-' + name + '.png').writeAsBytesSync(await tab.screenshot());
      await Future.delayed(const Duration(milliseconds: 420));
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': 5.0, 'y': 5.0 });
      await Future.delayed(const Duration(milliseconds: 950));
      final col = await tab.evaluate(_collectHoverJs());
      hoverOut[name] = jsonDecode(col is String ? col : jsonEncode(col));
    }
    result['hover'] = hoverOut;

    File(outDir + '/' + tag + '-footer.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('footer probe ok -> ' + outDir + '/' + tag + '-footer.json');
  } finally {
    await client.close();
  }
}

