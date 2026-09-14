// lens_probe_mail_hover2.dart — hunt the ref's giant-mail hover effect off the
// text node itself: elementFromPoint chains at the mail center (idle vs hover),
// SVG fill sampling, parent styles, and a MutationObserver catching nodes that
// appear under hover (tooltip / cursor morph / label).
// Usage: dart run tool/lens_probe_mail_hover2.dart <url> <outDir> <tag> [w] [h]
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

// find mail target, tag it + the svg + parents; return center
String _findJs() {
  return r"""
(() => {
  const f = document.querySelector('footer') || document.body;
  let el = f.querySelector('[data-footer-email]');
  let how = 'data-footer-email';
  if (!el) {
    const svgText = [...f.querySelectorAll('text, tspan')].find(t => /@/.test(t.textContent || ''));
    if (svgText) { el = svgText; how = 'svg-text'; }
  }
  if (!el) {
    el = [...f.querySelectorAll('a')].find(a => /@/.test(a.textContent || '') && a.getBoundingClientRect().width > 200);
    if (el) how = 'mail-a-200';
  }
  if (!el) return JSON.stringify({ found: false });
  el.setAttribute('data-probe-mail', '1');
  const r = el.getBoundingClientRect();
  const fillOf = (t) => { try { return getComputedStyle(t).fill; } catch (e) { return null; } };
  const svg = el.closest('svg');
  const parent = el.parentElement;
  const wrap = svg ? svg.parentElement : parent;
  const info = (e, depth) => {
    if (!e) return null;
    const cs = getComputedStyle(e);
    const rr = e.getBoundingClientRect();
    return { depth, tag: e.tagName, cls: ((e.getAttribute && e.getAttribute('class')) || '').slice(0, 60), x: Math.round(rr.x), y: Math.round(rr.y), w: Math.round(rr.width), h: Math.round(rr.height), fill: fillOf(e), color: cs.color, opacity: cs.opacity, transform: cs.transform, cursor: cs.cursor, pointerEvents: cs.pointerEvents };
  };
  return JSON.stringify({
    found: true, how, tag: el.tagName,
    text: (el.textContent || '').trim().slice(0, 80),
    cx: Math.round(r.x + r.width / 2), cy: Math.round(r.y + r.height / 2),
    elFill: fillOf(el), svgFill: svg ? fillOf(svg) : null,
    chain: [info(el, 0), info(svg, 1), info(wrap, 2), info(wrap ? wrap.parentElement : null, 3)]
  });
})()
""";
}

// elementFromPoint chain at (cx, cy): what is physically on top there
String _topJs(num cx, num cy) {
  return """
(() => {
  const out = [];
  let e = document.elementFromPoint(""" + cx.toString() + ", " + cy.toString() + r""");
  for (let i = 0; e && i < 6; i++) {
    const cs = getComputedStyle(e);
    const r = e.getBoundingClientRect();
    out.push({ i, tag: e.tagName, cls: ((e.getAttribute && e.getAttribute('class')) || '').slice(0, 60), text: (e.textContent || '').trim().slice(0, 40), x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height), pos: cs.position, z: cs.zIndex, bg: cs.backgroundColor, border: cs.borderRadius, color: cs.color, fill: (function(){ try { return getComputedStyle(e).fill; } catch (err) { return null; } })(), pointerEvents: cs.pointerEvents, font: cs.fontSize + '/' + cs.fontWeight });
    e = e.parentElement;
  }
  return JSON.stringify(out);
})()
""";
}

// arm MutationObserver + fill sampler on the tagged mail
String _armJs() {
  return r"""
(() => {
  const el = document.querySelector('[data-probe-mail]');
  if (!el) return 'missing';
  window.__MUT = [];
  window.__MO = new MutationObserver((muts) => {
    for (const m of muts) {
      for (const n of m.addedNodes) {
        if (n.nodeType === 1) window.__MUT.push({ html: (n.outerHTML || '').slice(0, 220), cls: ((n.getAttribute && n.getAttribute('class')) || '') });
      }
    }
  });
  window.__MO.observe(document.body, { childList: true, subtree: true });
  window.__FS = [];
  const t0 = performance.now();
  const svg = el.closest ? el.closest('svg') : null;
  const fillOf = (t) => { try { return getComputedStyle(t).fill; } catch (e) { return null; } };
  const snap = () => {
    const o = { t: Math.round(performance.now() - t0), fill: fillOf(el), opacity: getComputedStyle(el).opacity, transform: getComputedStyle(el).transform };
    if (svg) { o.svgFill = fillOf(svg); o.svgTransform = getComputedStyle(svg).transform; }
    window.__FS.push(o);
    if (performance.now() - t0 < 1500) requestAnimationFrame(snap);
  };
  requestAnimationFrame(snap);
  return 'armed';
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

    final idle = _jd(await tab.evaluate(_findJs()));
    result['idle'] = idle;
    if (idle is Map && idle['found'] == true) {
      final cx = (idle['cx'] as num).toDouble();
      final cy = (idle['cy'] as num).toDouble();
      result['topIdle'] = _jd(await tab.evaluate(_topJs(cx, cy)));

      result['armed'] = await tab.evaluate(_armJs());
      await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': cx, 'y': cy });
      await Future.delayed(const Duration(milliseconds: 1700));
      result['topHover'] = _jd(await tab.evaluate(_topJs(cx, cy)));
      result['fills'] = _jd(await tab.evaluate(r"(() => JSON.stringify({ n: (window.__FS || []).length, s: (window.__FS || []).filter((_, i) => i % 15 === 0), mut: (window.__MUT || []).slice(0, 8) }))()"));
    }

    File(outDir + '/' + tag + '-probe2.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('mail2 ok -> ' + outDir + '/' + tag + '-probe2.json');
  } finally {
    await client.close();
  }
}
