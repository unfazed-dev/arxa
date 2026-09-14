// lens_probe_pricing_faq.dart — pricing + FAQ parity probe. Places
// #pricing top at 40px, snapshots every pricing element (rect + computed
// styles + copy), then #faq top at 110px likewise, then clicks the second
// FAQ row and captures the open state. Also walks a depth-limited DOM tree
// of each section so a structurally different reference still yields
// comparable numbers. Run on both sites; the reference decides.
// Usage: dart run tool/lens_probe_pricing_faq.dart <url> [w] [h] [outDir] [tag]
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

String _snapJs() {
  return r'''
(() => {
  const y0 = window.scrollY;
  const clsOf = (e) => { const c = e.className; return String(c && c.baseVal !== undefined ? c.baseVal : c).slice(0, 60); };
  const pick = (el, doText) => {
    if (!el) return null;
    const cs = getComputedStyle(el);
    if (cs.display === 'none') return null;
    const r = el.getBoundingClientRect();
    const out = {
      tag: el.tagName.toLowerCase(),
      cls: clsOf(el),
      rect: { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1) },
      docTop: +(r.top + y0).toFixed(1),
      bg: cs.backgroundColor, color: cs.color,
      font: cs.fontSize + '/' + cs.fontWeight + ' ' + cs.fontFamily.split(',')[0].replace(/"/g, '') + ' lh=' + cs.lineHeight + ' ls=' + cs.letterSpacing,
      align: cs.textAlign,
      radius: cs.borderRadius,
      pad: cs.paddingTop + ' ' + cs.paddingRight + ' ' + cs.paddingBottom + ' ' + cs.paddingLeft,
      mar: cs.marginTop + ' ' + cs.marginRight + ' ' + cs.marginBottom + ' ' + cs.marginLeft,
      border: cs.borderTopWidth + ' ' + cs.borderRightWidth + ' ' + cs.borderBottomWidth + ' ' + cs.borderLeftWidth + ' bc=' + cs.borderBottomColor,
      shadow: cs.boxShadow === 'none' ? 'none' : cs.boxShadow.slice(0, 90),
      filter: cs.filter, gap: cs.gap, opacity: cs.opacity,
      transform: cs.transform === 'none' ? 'none' : cs.transform.slice(0, 70),
      display: cs.display, fit: cs.objectFit
    };
    if (doText) out.text = (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 400);
    return out;
  };
  const q1 = (sel, t) => { try { const el = document.querySelector(sel); return el ? pick(el, t) : null; } catch (e) { return null; } };
  const qn = (sel, n, t) => { try { return [...document.querySelectorAll(sel)].slice(0, n).map(e => pick(e, t)); } catch (e) { return []; } };
  const findSec = (id) => document.getElementById(id) || document.querySelector('[id*="' + id + '"], [class*="' + id + '"]');
  const tree = (root, maxDepth) => {
    const nodes = [];
    let count = 0;
    const walk = (el, depth, path) => {
      if (depth > maxDepth || count > 220) return;
      const p = pick(el, el.children.length === 0);
      if (p) { p.path = path; nodes.push(p); count++; }
      [...el.children].forEach((ch, i) => walk(ch, depth + 1, path + '.' + i));
    };
    if (root) walk(root, 0, 'r');
    return nodes;
  };
  const ps = findSec('pricing');
  const fs = findSec('faq');
  const pricing = ps ? {
    id: ps.id || null, tag: ps.tagName.toLowerCase(), cls: clsOf(ps),
    rect: (() => { const r = ps.getBoundingClientRect(); return { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1) }; })(),
    docTop: +(ps.getBoundingClientRect().top + y0).toFixed(1),
    cs: (() => { const c = getComputedStyle(ps); return { pad: c.paddingTop + ' ' + c.paddingRight + ' ' + c.paddingBottom + ' ' + c.paddingLeft, bg: c.backgroundColor }; })(),
    heading: q1('#pricing h2, [class*="pricing"] h2, [class*="pricing"] [class*="head"]', true),
    cards: qn('#pricing a, #pricing [class*="card"], #pricing [class*="tier"]', 6, true).filter(c => c && c.rect.h > 100),
    tree: tree(ps, 8)
  } : null;
  const faq = fs ? {
    id: fs.id || null, tag: fs.tagName.toLowerCase(), cls: clsOf(fs),
    rect: (() => { const r = fs.getBoundingClientRect(); return { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1) }; })(),
    docTop: +(fs.getBoundingClientRect().top + y0).toFixed(1),
    cs: (() => { const c = getComputedStyle(fs); return { pad: c.paddingTop + ' ' + c.paddingRight + ' ' + c.paddingBottom + ' ' + c.paddingLeft, bg: c.backgroundColor, maxW: c.maxWidth }; })(),
    heading: q1('#faq h2, [class*="faq"] h2, [class*="faq"] [class*="head"]', true),
    intro: q1('#faq [class*="intro"], #faq p', true),
    tree: tree(fs, 8)
  } : null;
  return JSON.stringify({ scrollY: y0, pricing: pricing, faq: faq });
})()
''';
}

String _faqDetailJs() {
  return r'''
(() => {
  const sec = document.getElementById('faq') || document.querySelector('[id*="faq"], [class*="faq"]');
  if (!sec) return JSON.stringify({ err: 'no faq' });
  const y0 = window.scrollY;
  const rows = [...sec.querySelectorAll('details')];
  const generic = rows.length === 0 ? [...sec.querySelectorAll('[aria-expanded]')] : [];
  const items = rows.length > 0 ? rows : generic;
  const states = items.map((it, i) => {
    const open = it.hasAttribute('open') ? true : (it.getAttribute('aria-expanded') === 'true');
    const r = it.getBoundingClientRect();
    return { i: i, open: open, h: +r.height.toFixed(1), docTop: +(r.top + y0).toFixed(1) };
  });
  const openIdx = states.findIndex(s => s.open);
  let answer = null, icon = null;
  if (openIdx >= 0) {
    const it = items[openIdx];
    const ans = it.parentElement ? [...it.parentElement.querySelectorAll('*')].filter(e => e !== it && !it.contains(e) && it.parentElement.contains(e)) : [];
    const cand = it.nextElementSibling || [...sec.querySelectorAll('p, [class*="answer"], [class*="panel"], [class*="content"]')].find(p => p.getBoundingClientRect().height > 10);
    if (cand) {
      const cs = getComputedStyle(cand); const r = cand.getBoundingClientRect();
      answer = { cls: String(cand.className).slice(0, 50), h: +r.height.toFixed(1), font: cs.fontSize + '/' + cs.fontWeight, color: cs.color, lh: cs.lineHeight, pad: cs.paddingTop + ' ' + cs.paddingRight + ' ' + cs.paddingBottom + ' ' + cs.paddingLeft, text: (cand.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 140) };
    }
    const svg = it.querySelector('svg');
    if (svg) {
      const cs = getComputedStyle(svg); const r = svg.getBoundingClientRect();
      const box = svg.parentElement ? getComputedStyle(svg.parentElement) : cs;
      icon = { size: r.width.toFixed(1) + 'x' + r.height.toFixed(1), color: cs.color, border: box.borderWidth + ' ' + box.borderColor, radius: box.borderRadius, transform: box.transform === 'none' ? 'none' : box.transform.slice(0, 50), parentCls: svg.parentElement ? String(svg.parentElement.className).slice(0, 40) : null };
    }
  }
  return JSON.stringify({ states: states, openIdx: openIdx, answer: answer, icon: icon });
})()
''';
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final width = args.length > 1 ? int.parse(args[1]) : 1713;
  final height = args.length > 2 ? int.parse(args[2]) : 1098;
  final outDir = args.length > 3 ? args[3] : '/tmp/arxa-compare/pf';
  final tag = args.length > 4 ? args[4] : 'ours';
  Directory(outDir).createSync(recursive: true);
  final result = <String, dynamic>{ 'url': url, 'viewport': '$width x $height', 'tag': tag };
  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: 700);
    final w = Stopwatch()..start();
    var revealed = false;
    while (w.elapsedMilliseconds < 30000) {
      final ok = await tab.evaluate(_revealJs());
      if (ok == true) { revealed = true; break; }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    result['revealed'] = revealed;
    await Future.delayed(const Duration(milliseconds: 800));
    await tab.evaluate(r'''(() => { const btn = [...document.querySelectorAll('button')].find(b => /^(accept)$/i.test((b.textContent || '').trim())); if (btn) btn.click(); return !!btn; })()''');
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
    result['pricingScrollY'] = await tab.evaluate(r'''window.scrollY''');
    result['snap'] = await tab.evaluate(_snapJs());
    await tab.evaluate(r'''(() => { document.querySelectorAll('video').forEach(v => v.pause()); return 1; })()''');
    await Future.delayed(const Duration(milliseconds: 300));
    File(outDir + '/' + tag + '-pricing.png').writeAsBytesSync(await tab.screenshot());

    await converge('faq', 110);
    await Future.delayed(const Duration(milliseconds: 600));
    result['faqScrollY'] = await tab.evaluate(r'''window.scrollY''');
    result['snap2'] = await tab.evaluate(_snapJs());
    result['faqDetail'] = await tab.evaluate(_faqDetailJs());
    File(outDir + '/' + tag + '-faq.png').writeAsBytesSync(await tab.screenshot());

    // open the second row (generic selector set; ref markup may differ)
    final clicked = await tab.evaluate(r'''
(() => {
  const sec = document.getElementById('faq') || document.querySelector('[id*="faq"], [class*="faq"]');
  if (!sec) return 'no-faq';
  let rows = [...sec.querySelectorAll('details > summary, details')].filter(e => e.tagName === 'SUMMARY' || e.tagName === 'DETAILS');
  if (rows.length === 0) rows = [...sec.querySelectorAll('[aria-expanded]')];
  if (rows.length < 2) return 'rows=' + rows.length;
  const target = rows.length > 2 ? rows[2] : rows[1];
  target.click();
  return 'ok:' + rows.indexOf(target);
})()
''');
    result['open2Click'] = clicked;
    await Future.delayed(const Duration(milliseconds: 700));
    result['faqDetailOpen2'] = await tab.evaluate(_faqDetailJs());
    File(outDir + '/' + tag + '-faq-open2.png').writeAsBytesSync(await tab.screenshot());

    File(outDir + '/' + tag + '.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('probe pricing/faq ok -> ' + outDir + '/' + tag + '.json');
  } finally {
    await client.close();
  }
}
