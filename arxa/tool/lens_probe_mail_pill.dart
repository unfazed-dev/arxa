// lens_probe_mail_pill.dart — dump the ref's floating cursor pill during
// (a) hover over the giant mail and (b) hover over a neutral footer spot:
// full outerHTML of pill candidates, their rects/text, plus the cursor arms.
// Usage: dart run tool/lens_probe_mail_pill.dart <url> <outDir> <tag> [w] [h]
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

// find mail center (svg text on ref, data-footer-email on ours)
String _findJs() {
  return r"""
(() => {
  const f = document.querySelector('footer') || document.body;
  let el = f.querySelector('[data-footer-email]');
  if (!el) el = [...f.querySelectorAll('text, tspan')].find(t => /@/.test(t.textContent || ''));
  if (!el) return JSON.stringify({ found: false });
  const r = el.getBoundingClientRect();
  return JSON.stringify({ found: true, cx: Math.round(r.x + r.width / 2), cy: Math.round(r.y + r.height / 2) });
})()
""";
}

// find a neutral footer hover spot: the copyright / a word in the footer top rows
String _neutralJs() {
  return r"""
(() => {
  const f = document.querySelector('footer') || document.body;
  const p = [...f.querySelectorAll('p, span, div')].filter(e => {
    const t = (e.textContent || '').trim();
    return t.length > 8 && t.length < 60 && !/@/.test(t) && e.getBoundingClientRect().height > 10 && e.getBoundingClientRect().height < 60 && e.getBoundingClientRect().y > 520;
  });
  if (!p.length) return JSON.stringify({ found: false });
  const r = p[0].getBoundingClientRect();
  return JSON.stringify({ found: true, text: (p[0].textContent || '').trim().slice(0, 30), cx: Math.round(r.x + Math.min(r.width / 2, 200)), cy: Math.round(r.y + r.height / 2) });
})()
""";
}

// dump pill/cursor candidates: small fixed/absolute dark pills + cursor svg groups
String _pillJs() {
  return r"""
(() => {
  const out = [];
  const els = [...document.querySelectorAll('div, a, span, g, svg')];
  for (const e of els) {
    const cs = getComputedStyle(e);
    const r = e.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) continue;
    const pillLike = (cs.position === 'fixed' || cs.position === 'absolute') && (parseFloat(cs.borderRadius) >= 40 || e.tagName === 'g') && r.width < 500 && r.height < 160 && e.closest('footer, body') ;
    const darkPill = cs.backgroundColor === 'rgb(10, 13, 18)' && parseFloat(cs.borderRadius) >= 40 && r.width < 500;
    if (pillLike || darkPill) {
      out.push({ tag: e.tagName, cls: (e.getAttribute && (e.getAttribute('class')) || '').slice(0, 40), x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height), text: (e.textContent || '').trim().slice(0, 60), html: (e.outerHTML || '').slice(0, 500), pos: cs.position, transform: cs.transform.slice(0, 90), opacity: cs.opacity, bg: cs.backgroundColor, radius: cs.borderRadius, z: cs.zIndex });
    }
    if (out.length >= 6) break;
  }
  return JSON.stringify(out);
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
    await Future.delayed(const Duration(milliseconds: 600));

    final mail = _jd(await tab.evaluate(_findJs()));
    final neutral = _jd(await tab.evaluate(_neutralJs()));
    result['mail'] = mail;
    result['neutral'] = neutral;

    // baseline pill state over neutral spot
    if (neutral is Map && neutral['found'] == true) {
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': (neutral['cx'] as num).toDouble(), 'y': (neutral['cy'] as num).toDouble() });
      await Future.delayed(const Duration(milliseconds: 1200));
      result['pillNeutral'] = _jd(await tab.evaluate(_pillJs()));
    }

    // pill state over the giant mail
    if (mail is Map && mail['found'] == true) {
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': 5.0, 'y': 5.0 });
      await Future.delayed(const Duration(milliseconds: 400));
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': (mail['cx'] as num).toDouble(), 'y': (mail['cy'] as num).toDouble() });
      await Future.delayed(const Duration(milliseconds: 1200));
      result['pillMail'] = _jd(await tab.evaluate(_pillJs()));
      File(outDir + '/' + tag + '-pill-mail.png').writeAsBytesSync(await tab.screenshot());
    }

    File(outDir + '/' + tag + '-pill.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('pill ok -> ' + outDir + '/' + tag + '-pill.json');
  } finally {
    await client.close();
  }
}
