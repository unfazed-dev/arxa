// lens_probe_pf_anatomy.dart — identify the reference FAQ animation targets:
// per-element computed transition inventory after a toggle + open/closed
// computed geometry (max-height, padding, overflow, transform) of every row
// descendant. Usage: dart run tool/lens_probe_pf_anatomy.dart <url> <outJson>
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

String _treeJs() {
  return r"""
(() => {
  const sec = document.getElementById('faq') || document.querySelector('[id*="faq"], [class*="faq"]');
  const btns = [...sec.querySelectorAll('button')];
  const clsOf = (el) => {
    if (!el.className) return '';
    return typeof el.className === 'string' ? el.className : (el.className.baseVal || '');
  };
  const tree = (el, d) => {
    if (!el || d > 5) return null;
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    return {
      tag: el.tagName.toLowerCase(), cls: clsOf(el),
      x: Math.round(r.x), y: Math.round((r.y + window.scrollY) * 10) / 10, h: Math.round(r.height * 100) / 100, w: Math.round(r.width * 100) / 100,
      pad: cs.padding, mar: cs.margin, maxH: cs.maxHeight, hgt: cs.height, ov: cs.overflow, op: cs.opacity, tr: cs.transform,
      trans: cs.transitionProperty + ' | ' + cs.transitionDuration + ' | ' + cs.transitionTimingFunction,
      kids: [...el.children].map(c => tree(c, d + 1))
    };
  };
  return JSON.stringify(btns.slice(0, 2).map(b => tree(b.parentElement, 0)));
})()
""";
}

String _animTargetsJs() {
  return r"""
(() => {
  const sec = document.getElementById('faq') || document.querySelector('[id*="faq"], [class*="faq"]');
  const btns = [...sec.querySelectorAll('button')];
  const clsOf = (el) => {
    if (!el.className) return '';
    return typeof el.className === 'string' ? el.className : (el.className.baseVal || '');
  };
  const out = [];
  btns.slice(0, 2).forEach((b, i) => {
    const row = b.parentElement;
    const walk = (el, path) => {
      (el.getAnimations ? el.getAnimations() : []).forEach(a => {
        const ct = a.effect ? a.effect.getComputedTiming() : null;
        out.push({ row: i, el: path + '>' + el.tagName.toLowerCase() + (clsOf(el) ? '.' + clsOf(el) : ''), cls: a.constructor.name, prop: a.transitionProperty || null, dur: ct ? ct.duration : null, ease: ct ? ct.easing : null });
      });
      [...el.children].forEach((c, j) => walk(c, path + '>' + el.tagName.toLowerCase() + j));
    };
    walk(row, 'row');
  });
  return JSON.stringify(out);
})()
""";
}

String _clickRow1Js() {
  return r"""
(() => { const sec = document.getElementById('faq') || document.querySelector('[id*="faq"], [class*="faq"]'); const btns = [...sec.querySelectorAll('button')]; btns[1].click(); return btns.length; })()
""";
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'https://umanodesign.studio/';
  final outJson = args.length > 1 ? args[1] : '/tmp/arxa-compare/pf/ref-anatomy.json';
  final result = <String, dynamic>{ 'url': url };
  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(args.length > 2 ? int.parse(args[2]) : 1713, args.length > 3 ? int.parse(args[3]) : 1098);
    await tab.navigateAndSettle(url, settleMs: 700);
    final w = Stopwatch()..start();
    while (w.elapsedMilliseconds < 30000) {
      final ok = await tab.evaluate(_revealJs());
      if (ok == true) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await Future.delayed(const Duration(milliseconds: 800));
    await tab.evaluate(r"""
(() => { const btn = [...document.querySelectorAll('button')].find(b => /^(accept)$/i.test((b.textContent || '').trim())); if (btn) btn.click(); return 1; })()
""");
    await Future.delayed(const Duration(milliseconds: 400));
    for (int i = 0; i < 6; i++) {
      final s = await tab.evaluate(r"""
(() => { const el = document.getElementById('faq') || document.querySelector('[id*="faq"], [class*="faq"]'); return el ? el.getBoundingClientRect().top : null; })()
""");
      final top = (s is num) ? s.toDouble() : null;
      if (top != null && (top.round() - 110).abs() < 5) break;
      await tab.evaluate(r"""
(() => { window.scrollBy(0, ARG); return window.scrollY; })()
""".replaceAll('ARG', ((top ?? 0).round() - 110).toString()));
      await Future.delayed(const Duration(milliseconds: 650));
    }
    await Future.delayed(const Duration(milliseconds: 800));

    final pre = await tab.evaluate(_treeJs());
    result['pre'] = jsonDecode(pre is String ? pre : jsonEncode(pre));
    await tab.evaluate(_clickRow1Js());
    await Future.delayed(const Duration(milliseconds: 80));
    final targets = await tab.evaluate(_animTargetsJs());
    result['targets'] = jsonDecode(targets is String ? targets : jsonEncode(targets));
    await Future.delayed(const Duration(milliseconds: 900));
    final post = await tab.evaluate(_treeJs());
    result['post'] = jsonDecode(post is String ? post : jsonEncode(post));

    File(outJson).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('anatomy ok -> ' + outJson);
  } finally {
    await client.close();
  }
}

