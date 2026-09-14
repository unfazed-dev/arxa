// lens_probe_parallax.dart — hunt the scroll-linked motion around the footer:
// inventory dark containers near the page bottom, then sample scrollY vs
// footer/black-container viewport rects over the last ~1800px of scroll to
// expose parallax factors or a sticky/fixed reveal. Frames at 3 positions.
// Usage: dart run tool/lens_probe_parallax.dart <url> <outDir> <tag> [w] [h]
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

String _inventoryJs() {
  return r"""
(() => {
  const out = { vw: window.innerWidth, vh: window.innerHeight, sh: document.documentElement.scrollHeight, y: window.scrollY, dark: [], bodyKids: [] };
  const footer = document.querySelector('footer') || [...document.querySelectorAll('div,section')].find(el => /footer/i.test(String(el.className)) && el.getBoundingClientRect().height > 300);
  if (footer) {
    const r = footer.getBoundingClientRect(); const cs = getComputedStyle(footer);
    out.footer = { cls: String(footer.className).slice(0, 80), yDoc: Math.round(r.y + window.scrollY), h: Math.round(r.height), bg: cs.backgroundColor, pos: cs.position, z: cs.zIndex };
  }
  [...document.querySelectorAll('body *')].forEach(el => {
    const cs = getComputedStyle(el); const r = el.getBoundingClientRect();
    if (r.width < window.innerWidth * 0.6 || r.height < 200) return;
    let dark = false; let how = '';
    const m = cs.backgroundColor.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
    if (m && (Number(m[1]) + Number(m[2]) + Number(m[3])) < 160) { dark = true; how = 'bg'; }
    if (!dark && cs.backgroundImage && cs.backgroundImage.includes('gradient')) {
      const gs = cs.backgroundImage.match(/rgba?\(\d+,\s*\d+,\s*\d+/g) || [];
      if (gs.some(s => { const n = s.match(/(\d+),\s*(\d+),\s*(\d+)/); return n && (Number(n[1]) + Number(n[2]) + Number(n[3])) < 160; })) { dark = true; how = 'grad'; }
    }
    if (!dark && cs.backgroundImage && /url\(/.test(cs.backgroundImage)) { dark = true; how = 'img'; }
    if (dark) out.dark.push({ tag: el.tagName.toLowerCase(), cls: String(el.className).slice(0, 70), how, yDoc: Math.round(r.y + window.scrollY), h: Math.round(r.height), w: Math.round(r.width), bg: cs.backgroundColor.slice(0, 40), bgi: cs.backgroundImage.slice(0, 100), pos: cs.position, z: cs.zIndex, tr: cs.transform === 'none' ? '' : cs.transform.slice(0, 60) });
  });
  out.dark.sort((a, b) => a.yDoc - b.yDoc);
  const walk = (el, depth) => {
    if (depth > 2) return;
    [...el.children].forEach(c => {
      const r = c.getBoundingClientRect(); const cs = getComputedStyle(c);
      if (r.height > 150) out.bodyKids.push({ d: depth, tag: c.tagName.toLowerCase(), cls: String(c.className).slice(0, 60), yDoc: Math.round(r.y + window.scrollY), h: Math.round(r.height), bg: cs.backgroundColor.slice(0, 30) });
      walk(c, depth + 1);
    });
  };
  walk(document.body, 0);
  return JSON.stringify(out);
})()
""";
}

String _sampleJs() {
  return r"""
(() => {
  const footer = document.querySelector('footer') || [...document.querySelectorAll('div,section')].find(el => /footer/i.test(String(el.className)) && el.getBoundingClientRect().height > 300);
  const pick = (el) => { const r = el.getBoundingClientRect(); const cs = getComputedStyle(el); return { y: Math.round(r.y * 10) / 10, h: Math.round(r.height * 10) / 10, tr: cs.transform === 'none' ? '' : cs.transform, pos: cs.position, top: cs.top, bot: cs.bottom }; };
  let black = null;
  [...document.querySelectorAll('body *')].forEach(el => {
    const cs = getComputedStyle(el); const r = el.getBoundingClientRect();
    if (r.width < window.innerWidth * 0.6 || r.height < 200) return;
    const m = cs.backgroundColor.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
    if (m && (Number(m[1]) + Number(m[2]) + Number(m[3])) < 160) {
      if (!black) black = el;
      else { const rb = black.getBoundingClientRect(); if (r.bottom > rb.bottom) black = el; }
    }
  });
  const out = { y: window.scrollY, footer: footer ? pick(footer) : null, black: black ? Object.assign(pick(black), { cls: String(black.className).slice(0, 60) }) : null };
  return JSON.stringify(out);
})()
""";
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final outDir = args.length > 1 ? args[1] : '/tmp/arxa-compare/par';
  final tag = args.length > 2 ? args[2] : 'par';
  final w = args.length > 3 ? int.parse(args[3]) : 1713;
  final h = args.length > 4 ? int.parse(args[4]) : 1098;
  Directory(outDir).createSync(recursive: true);
  final result = <String, dynamic>{ 'url': url, 'tag': tag, 'vw': w, 'vh': h };
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

    final invTop = await tab.evaluate(_inventoryJs());
    result['inventoryTop'] = jsonDecode(invTop is String ? invTop : jsonEncode(invTop));

    await tab.evaluate(r"(() => { window.scrollTo(0, document.body.scrollHeight); return window.scrollY; })()");
    await Future.delayed(const Duration(milliseconds: 1600));

    final invBot = await tab.evaluate(_inventoryJs());
    result['inventoryBottom'] = jsonDecode(invBot is String ? invBot : jsonEncode(invBot));

    final sh = ((result['inventoryBottom'] as Map)['sh'] as num).toDouble();
    final fracs = <double>[-1800, -1500, -1200, -900, -600, -300, -150, 0];
    final steps = <Map<String, dynamic>>[];
    for (var i = 0; i < fracs.length; i++) {
      final target = (sh + fracs[i]).clamp(0.0, sh);
      await tab.evaluate('(() => { window.scrollTo(0, $target); return window.scrollY; })()');
      await Future.delayed(const Duration(milliseconds: 450));
      final s = await tab.evaluate(_sampleJs());
      final sm = jsonDecode(s is String ? s : jsonEncode(s)) as Map<String, dynamic>;
      sm['target'] = target;
      steps.add(sm);
      if (i == 0 || i == 4 || i == 7) {
        File(outDir + '/' + tag + '-scroll-' + i.toString() + '.png').writeAsBytesSync(await tab.screenshot());
      }
    }
    result['steps'] = steps;
    File(outDir + '/' + tag + '-parallax.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('parallax ok -> ' + outDir + '/' + tag + '-parallax.json');
  } finally {
    await client.close();
  }
}
