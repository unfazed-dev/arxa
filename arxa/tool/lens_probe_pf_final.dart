// lens_probe_pf_final.dart — final pricing/FAQ parity capture: matched
// compositions (pricing top 40, faq top 110), computed icon strokes, and
// the open-row-2 interaction (details on ours, buttons on the reference).
// Usage: dart run tool/lens_probe_pf_final.dart <url> <outDir> <tag>
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

String _iconJs() {
  return r'''
(() => {
  const svgs = [...document.querySelectorAll('#faq svg')];
  return JSON.stringify(svgs.slice(0, 3).map((s) => {
    const c = s.querySelector('circle');
    const ps = [...s.querySelectorAll('path')];
    return {
      circleStroke: c ? getComputedStyle(c).stroke : null,
      pathStrokes: ps.map(p => getComputedStyle(p).stroke),
      circleOpacity: c ? getComputedStyle(c).opacity : null,
      vOpacity: ps.length > 1 ? getComputedStyle(ps[1]).opacity : null,
      w: s.getBoundingClientRect().width.toFixed(1)
    };
  }));
})()
''';
}

String _stateJs() {
  return r'''
(() => {
  const sec = document.getElementById('faq') || document.querySelector('[id*="faq"], [class*="faq"]');
  const y0 = window.scrollY;
  const g = (el) => { const r = el.getBoundingClientRect(); return { h: +r.height.toFixed(1), y: +r.y.toFixed(1), docTop: +(r.top + y0).toFixed(1) }; };
  const details = [...sec.querySelectorAll('details')];
  if (details.length > 0) {
    const rows = details.map(d => { const r = g(d); const q = d.querySelector('.faq-question-text') || d.querySelector('p'); const qc = q ? getComputedStyle(q).color : null; const bg = getComputedStyle(d).backgroundColor; return { h: r.h, docTop: r.docTop, open: d.hasAttribute('open'), qColor: qc, bg: bg }; });
    return JSON.stringify({ kind: 'details', rows: rows });
  }
  const buttons = [...sec.querySelectorAll('button')];
  const rows = buttons.map(b => { const row = b.parentElement; const r = g(row); const q = b.querySelector('p') || b; const qc = getComputedStyle(q).color; const bg = getComputedStyle(row).backgroundColor; const svg = b.querySelector('svg'); const circ = svg ? svg.querySelector('circle') : null; return { h: r.h, docTop: r.docTop, qColor: qc, bg: bg, iconStroke: circ ? getComputedStyle(circ).stroke : null }; });
  return JSON.stringify({ kind: 'buttons', rows: rows.slice(0, 6) });
})()
''';
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final outDir = args.length > 1 ? args[1] : '/tmp/arxa-compare/pf';
  final tag = args.length > 2 ? args[2] : 'ours-final';
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
    await tab.evaluate(r'''(() => { const btn = [...document.querySelectorAll('button')].find(b => /^(accept)$/i.test((b.textContent || '').trim())); if (btn) btn.click(); return 1; })()''');
    await Future.delayed(const Duration(milliseconds: 400));

    Future<bool> converge(String id, int target) async {
      for (int i = 0; i < 6; i++) {
        final s = await tab.evaluate(r'''(() => { const el = document.getElementById(ARG) || document.querySelector('[id*="ARG"], [class*="ARG"]'); return el ? el.getBoundingClientRect().top : null; })()'''.replaceAll('ARG', id));
        final top = (s is num) ? s.toDouble() : null;
        if (top == null) return false;
        final delta = top.round() - target;
        if (delta.abs() < 5) return true;
        await tab.evaluate(r'''(() => { window.scrollBy(0, ARG); return window.scrollY; })()'''.replaceAll('ARG', delta.toString()));
        await Future.delayed(const Duration(milliseconds: 650));
      }
      return true;
    }

    await converge('pricing', 40);
    await Future.delayed(const Duration(milliseconds: 600));
    await tab.evaluate(r'''(() => { document.querySelectorAll('video').forEach(v => v.pause()); return 1; })()''');
    await Future.delayed(const Duration(milliseconds: 300));
    File(outDir + '/' + tag + '-pricing.png').writeAsBytesSync(await tab.screenshot());

    await converge('faq', 110);
    await Future.delayed(const Duration(milliseconds: 600));
    result['icons'] = await tab.evaluate(_iconJs());
    result['stateDefault'] = await tab.evaluate(_stateJs());
    File(outDir + '/' + tag + '-faq.png').writeAsBytesSync(await tab.screenshot());

    final clicked = await tab.evaluate(r'''
(() => {
  const sec = document.getElementById('faq') || document.querySelector('[id*="faq"], [class*="faq"]');
  if (!sec) return 'no-faq';
  const details = [...sec.querySelectorAll('details')];
  if (details.length >= 2) { details[1].querySelector('summary').click(); return 'details1'; }
  const buttons = [...sec.querySelectorAll('button')];
  if (buttons.length >= 2) { buttons[1].click(); return 'button1'; }
  return 'none';
})()
''');
    result['open2Click'] = clicked;
    await Future.delayed(const Duration(milliseconds: 800));
    result['stateOpen2'] = await tab.evaluate(_stateJs());
    File(outDir + '/' + tag + '-faq-open2.png').writeAsBytesSync(await tab.screenshot());

    File(outDir + '/' + tag + '.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('final probe ok -> ' + outDir + '/' + tag + '.json');
  } finally {
    await client.close();
  }
}
