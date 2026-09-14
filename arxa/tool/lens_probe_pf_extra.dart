// lens_probe_pf_extra.dart — the last ground-truth numbers for pricing+FAQ:
// pricing CTA radius/bg/font, FAQ icon stroke colors (open + closed), and
// the 390px mobile paddings/type for both sections (per site).
// Usage: dart run tool/lens_probe_pf_extra.dart <url> <outJson> <tag>
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

String _deskJs() {
  return r'''
(() => {
  const out = {};
  const cta = [...document.querySelectorAll('#pricing a > div, #pricing a > span')].pop();
  if (cta) {
    const cs = getComputedStyle(cta);
    out.cta = { tag: cta.tagName.toLowerCase(), radius: cs.borderRadius, bg: cs.backgroundColor, color: cs.color, font: cs.fontSize + '/' + cs.fontWeight + ' ' + cs.fontFamily.split(',')[0], lh: cs.lineHeight, pad: cs.paddingTop + ' ' + cs.paddingRight + ' ' + cs.paddingBottom + ' ' + cs.paddingLeft, h: cta.getBoundingClientRect().height.toFixed(1), mar: cs.marginTop + ' ' + cs.marginRight + ' ' + cs.marginBottom + ' ' + cs.marginLeft };
  }
  const svgs = [...document.querySelectorAll('#faq svg')];
  out.icons = svgs.slice(0, 3).map((s, i) => {
    const cs = getComputedStyle(s);
    const circ = s.querySelector('circle');
    const paths = [...s.querySelectorAll('path')].map(p => ({ d: (p.getAttribute('d') || '').slice(0, 24), stroke: p.getAttribute('stroke'), sw: p.getAttribute('stroke-width') }));
    return { i: i, parentColor: cs.color, circleStroke: circ ? circ.getAttribute('stroke') : null, circleSw: circ ? circ.getAttribute('stroke-width') : null, w: s.getBoundingClientRect().width.toFixed(1), paths: paths, cls: String(s.parentElement.className).slice(0, 40) };
  });
  const q0 = document.querySelector('#faq details[open] .faq-question-text, #faq [open] p');
  if (q0) { const cs = getComputedStyle(q0); out.qOpen = { color: cs.color, font: cs.fontSize + '/' + cs.fontWeight }; }
  return JSON.stringify(out);
})()
''';
}

String _mobileJs() {
  return r'''
(() => {
  const y0 = window.scrollY;
  const g = (el) => {
    if (!el) return null;
    const cs = getComputedStyle(el); const r = el.getBoundingClientRect();
    return { rect: { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1) }, docTop: +(r.top + y0).toFixed(1), pad: cs.paddingTop + ' ' + cs.paddingRight + ' ' + cs.paddingBottom + ' ' + cs.paddingLeft, font: cs.fontSize + '/' + cs.fontWeight + ' lh=' + cs.lineHeight, mar: cs.marginTop + ' ' + cs.marginRight + ' ' + cs.marginBottom + ' ' + cs.marginLeft };
  };
  const ps = document.getElementById('pricing');
  const fs = document.getElementById('faq');
  const out = { scrollY: y0 };
  if (ps) {
    out.pricing = g(ps);
    out.pHeading = g(ps.querySelector('h2'));
    out.pCards = [...ps.querySelectorAll('a')].slice(0, 3).map(a => { const r = a.getBoundingClientRect(); return { w: +r.width.toFixed(1), h: +r.height.toFixed(1), x: +r.x.toFixed(1), docTop: +(r.top + y0).toFixed(1) }; });
  }
  if (fs) {
    out.faq = g(fs);
    out.fHeading = g(fs.querySelector('h2'));
    out.fIntro = g(fs.querySelector('p'));
    const rows = [...fs.querySelectorAll('details')];
    out.fRows = rows.slice(0, 3).map(d => { const r = d.getBoundingClientRect(); const s = d.querySelector('summary'); const sc = s ? getComputedStyle(s) : null; const sr = s ? s.getBoundingClientRect() : null; return { h: +r.height.toFixed(1), w: +r.width.toFixed(1), docTop: +(r.top + y0).toFixed(1), open: d.hasAttribute('open'), qFont: sc ? sc.fontSize + '/' + sc.fontWeight : null, qPad: sc ? sc.paddingTop + ' ' + sc.paddingRight + ' ' + sc.paddingBottom + ' ' + sc.paddingLeft : null, qH: sr ? +sr.height.toFixed(1) : null }; });
    const ans = document.querySelector('#faq details[open] p:not(summary p)');
    if (ans) { const cs = getComputedStyle(ans); const r = ans.getBoundingClientRect(); out.fAnswer = { h: +r.height.toFixed(1), font: cs.fontSize + '/' + cs.fontWeight + ' lh=' + cs.lineHeight, pad: cs.paddingTop + ' ' + cs.paddingRight + ' ' + cs.paddingBottom + ' ' + cs.paddingLeft, mar: cs.marginTop + ' ' + cs.marginRight + ' ' + cs.marginBottom + ' ' + cs.marginLeft }; }
  }
  return JSON.stringify(out);
})()
''';
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'https://umanodesign.studio/';
  final outPath = args.length > 1 ? args[1] : '/tmp/arxa-compare/pf/extra.json';
  final tag = args.length > 2 ? args[2] : 'ref';
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
    await Future.delayed(const Duration(milliseconds: 300));
    for (int i = 0; i < 6; i++) {
      final s = await tab.evaluate(r'''(() => { const el = document.getElementById('faq') || document.querySelector('[id*="faq"], [class*="faq"]'); return el ? el.getBoundingClientRect().top : null; })()''');
      final top = (s is num) ? s.toDouble() : null;
      if (top == null) break;
      final delta = top.round() - 110;
      if (delta.abs() < 5) break;
      await tab.evaluate(r'''(() => { window.scrollBy(0, ARG); return window.scrollY; })()'''.replaceAll('ARG', delta.toString()));
      await Future.delayed(const Duration(milliseconds: 650));
    }
    await Future.delayed(const Duration(milliseconds: 500));
    result['desktop'] = await tab.evaluate(_deskJs());

    await tab.setViewport(390, 844);
    await tab.evaluate(r'''window.scrollTo(0, 0)''');
    await Future.delayed(const Duration(milliseconds: 900));
    for (int i = 0; i < 8; i++) {
      final s = await tab.evaluate(r'''(() => { const el = document.getElementById('pricing') || document.querySelector('[id*="pricing"], [class*="pricing"]'); return el ? el.getBoundingClientRect().top : null; })()''');
      final top = (s is num) ? s.toDouble() : null;
      if (top == null) break;
      final delta = top.round() - 60;
      if (delta.abs() < 5) break;
      await tab.evaluate(r'''(() => { window.scrollBy(0, ARG); return window.scrollY; })()'''.replaceAll('ARG', delta.toString()));
      await Future.delayed(const Duration(milliseconds: 650));
    }
    await Future.delayed(const Duration(milliseconds: 600));
    result['mobilePricing'] = await tab.evaluate(_mobileJs());
    File(outPath.replaceAll('.json', '-m-pricing.png')).writeAsBytesSync(await tab.screenshot());
    for (int i = 0; i < 8; i++) {
      final s = await tab.evaluate(r'''(() => { const el = document.getElementById('faq') || document.querySelector('[id*="faq"], [class*="faq"]'); return el ? el.getBoundingClientRect().top : null; })()''');
      final top = (s is num) ? s.toDouble() : null;
      if (top == null) break;
      final delta = top.round() - 80;
      if (delta.abs() < 5) break;
      await tab.evaluate(r'''(() => { window.scrollBy(0, ARG); return window.scrollY; })()'''.replaceAll('ARG', delta.toString()));
      await Future.delayed(const Duration(milliseconds: 650));
    }
    await Future.delayed(const Duration(milliseconds: 600));
    result['mobileFaq'] = await tab.evaluate(_mobileJs());
    File(outPath.replaceAll('.json', '-m-faq.png')).writeAsBytesSync(await tab.screenshot());

    File(outPath).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('extra probe ok -> ' + outPath);
  } finally {
    await client.close();
  }
}
