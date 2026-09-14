// lens_probe_pf_motion.dart — FAQ open/close motion capture: rAF sampler
// (row heights, paddings, text colors, backgrounds, icon opacity/transform,
// answer height/opacity/transform) + a getAnimations() inventory taken just
// after the toggle click. Works on details-based DOMs (ours) and button+div
// DOMs (the reference). Also grabs mid-flight frames at ~120ms and ~280ms.
// Usage: dart run tool/lens_probe_pf_motion.dart <url> <outDir> <tag>
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

String _wireJs() {
  return r"""
(() => {
  const sec = document.getElementById('faq') || document.querySelector('[id*="faq"], [class*="faq"]');
  if (!sec) return JSON.stringify({ error: 'no-faq' });
  const det = [...sec.querySelectorAll('details')];
  let rows = [];
  let kind = 'buttons';
  if (det.length >= 2) {
    kind = 'details';
    rows = det.map(d => ({ row: d, q: d.querySelector('summary'), ans: d.querySelector('.faq-answer'), iconV: d.querySelector('.faq-icon-v'), icon: d.querySelector('.faq-icon'), txt: d.querySelector('.faq-question-text') }));
  } else {
    const btns = [...sec.querySelectorAll('button')];
    rows = btns.map(b => {
      const paths = b.querySelectorAll('svg path');
      let ans = b.nextElementSibling;
      if (!ans || ans === b) ans = b.parentElement.lastElementChild;
      return { row: b.parentElement, q: b, ans: ans, iconV: paths.length > 1 ? paths[1] : null, icon: b.querySelector('svg'), txt: b.querySelector('p') || b };
    });
  }
  const cs = (el, p) => { try { return el ? getComputedStyle(el)[p] : null; } catch (e) { return null; } };
  const h = (el) => { if (!el) return null; const r = el.getBoundingClientRect(); return Math.round(r.height * 100) / 100; };
  window.__MS = [];
  const t0 = performance.now();
  const loop = () => {
    const r0 = rows[0], r1 = rows[1];
    window.__MS.push({
      t: Math.round(performance.now() - t0),
      h0: h(r0.row), h1: h(r1.row),
      ans0: h(r0.ans), ans1: h(r1.ans),
      pad0: cs(r0.q, 'paddingBottom'), pad1: cs(r1.q, 'paddingBottom'),
      txt0: cs(r0.txt, 'color'),
      bg0: cs(r0.row, 'backgroundColor'), bg1: cs(r1.row, 'backgroundColor'),
      iv0: cs(r0.iconV, 'opacity'), iv1: cs(r1.iconV, 'opacity'),
      tr0: cs(r0.icon, 'transform'),
      ao0: cs(r0.ans, 'opacity'), at0: cs(r0.ans, 'transform')
    });
    if (performance.now() - t0 < 1500) requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
  rows[1].q.click();
  setTimeout(() => {
    const dump = (el, i) => {
      if (!el.getAnimations) return [];
      return el.getAnimations({ subtree: true }).map(a => {
        const ct = a.effect ? a.effect.getComputedTiming() : null;
        return { row: i, cls: a.constructor.name, prop: a.transitionProperty || null, dur: ct ? ct.duration : null, ease: ct && ct.easing !== undefined ? ct.easing : null };
      });
    };
    window.__ANIMS = rows.flatMap((r, i) => dump(r.row, i));
  }, 70);
  return kind;
})()
""";
}

String _clickFirstJs() {
  return r"""
(() => {
  const sec = document.getElementById('faq') || document.querySelector('[id*="faq"], [class*="faq"]');
  const det = [...sec.querySelectorAll('details')];
  if (det.length >= 2) { det[1].querySelector('summary').click(); return 'details1'; }
  const btns = [...sec.querySelectorAll('button')];
  if (btns.length >= 2) { btns[1].click(); return 'button1'; }
  return 'none';
})()
""";
}

String _acceptJs() {
  return r"""
(() => { const btn = [...document.querySelectorAll('button')].find(b => /^(accept)$/i.test((b.textContent || '').trim())); if (btn) btn.click(); return 1; })()
""";
}

String _topJs(String id) {
  return r"""
(() => { const el = document.getElementById('ID') || document.querySelector('[id*="ID"], [class*="ID"]'); return el ? el.getBoundingClientRect().top : null; })()
""".replaceAll('ID', id);
}

String _scrollJs(String delta) {
  return r"""
(() => { window.scrollBy(0, DELTA); return window.scrollY; })()
""".replaceAll('DELTA', delta);
}

String _collectJs() {
  return r"""
(() => JSON.stringify({ anims: window.__ANIMS || null, samples: window.__MS || null, n: (window.__MS || []).length }))()
""";
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final outDir = args.length > 1 ? args[1] : '/tmp/arxa-compare/pf';
  final tag = args.length > 2 ? args[2] : 'motion';
  final result = <String, dynamic>{ 'url': url, 'tag': tag };
  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1713, 1098);
    await tab.navigateAndSettle(url, settleMs: 700);
    final w = Stopwatch()..start();
    while (w.elapsedMilliseconds < 30000) {
      final ok = await tab.evaluate(_revealJs());
      if (ok == true) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await Future.delayed(const Duration(milliseconds: 800));
    await tab.evaluate(_acceptJs());
    await Future.delayed(const Duration(milliseconds: 400));

    Future<bool> converge(String id, int target) async {
      for (int i = 0; i < 6; i++) {
        final s = await tab.evaluate(_topJs(id));
        final top = (s is num) ? s.toDouble() : null;
        if (top == null) return false;
        final delta = top.round() - target;
        if (delta.abs() < 5) return true;
        await tab.evaluate(_scrollJs(delta.toString()));
        await Future.delayed(const Duration(milliseconds: 650));
      }
      return true;
    }

    await converge('faq', 110);
    await Future.delayed(const Duration(milliseconds: 800));

    final kind = await tab.evaluate(_wireJs());
    result['kind'] = kind is String ? kind : jsonEncode(kind);
    await Future.delayed(const Duration(milliseconds: 1900));
    final coll = await tab.evaluate(_collectJs());
    final s = coll is String ? coll : jsonEncode(coll);
    result['motion'] = jsonDecode(s);

    await tab.evaluate(_clickFirstJs());
    await Future.delayed(const Duration(milliseconds: 1100));
    await tab.evaluate(_clickFirstJs());
    await Future.delayed(const Duration(milliseconds: 120));
    File(outDir + '/' + tag + '-motion-120.png').writeAsBytesSync(await tab.screenshot());
    await Future.delayed(const Duration(milliseconds: 1000));
    await tab.evaluate(_clickFirstJs());
    await Future.delayed(const Duration(milliseconds: 280));
    File(outDir + '/' + tag + '-motion-280.png').writeAsBytesSync(await tab.screenshot());

    File(outDir + '/' + tag + '-motion.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('motion probe ok -> ' + outDir + '/' + tag + '-motion.json');
  } finally {
    await client.close();
  }
}

