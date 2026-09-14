// lens_probe_parallax2.dart — mechanism of the fixed-footer reveal: ancestor
// chain of the footer (position/top/bottom/z), body/html padding that extends
// scroll by the footer height, and (optional) two scroll samples for mobile.
// Usage: dart run tool/lens_probe_parallax2.dart <url> <out> <tag> [w] [h]
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

String _mechJs() {
  return r"""
(() => {
  const footer = document.querySelector('footer') || [...document.querySelectorAll('div,section')].find(el => /footer/i.test(String(el.className)) && el.getBoundingClientRect().height > 300);
  const chain = [];
  let el = footer;
  while (el && el !== document.documentElement) {
    const cs = getComputedStyle(el); const r = el.getBoundingClientRect();
    chain.push({ tag: el.tagName.toLowerCase(), cls: String(el.className).slice(0, 50), pos: cs.position, top: cs.top, bottom: cs.bottom, left: cs.left, w: Math.round(r.width), h: Math.round(r.height), y: Math.round(r.y), z: cs.zIndex, mt: cs.marginTop, mb: cs.marginBottom, pt: cs.paddingTop, pb: cs.paddingBottom });
    el = el.parentElement;
  }
  const bcs = getComputedStyle(document.body);
  const dcs = getComputedStyle(document.documentElement);
  const kids = [];
  [...document.body.children].forEach(c => {
    const r = c.getBoundingClientRect(); const cs = getComputedStyle(c);
    kids.push({ tag: c.tagName.toLowerCase(), cls: String(c.className).slice(0, 40), pos: cs.position, yDoc: Math.round(r.y + window.scrollY), h: Math.round(r.height), mt: cs.marginTop, mb: cs.marginBottom });
  });
  return JSON.stringify({ chain, body: { pb: bcs.paddingBottom, mb: bcs.marginBottom, h: Math.round(document.body.getBoundingClientRect().height) }, html: { pb: dcs.paddingBottom, sh: document.documentElement.scrollHeight, ch: document.documentElement.clientHeight }, bodyKids: kids });
})()
""";
}

String _sampleJs() {
  return r"""
(() => {
  const footer = document.querySelector('footer') || [...document.querySelectorAll('div,section')].find(el => /footer/i.test(String(el.className)) && el.getBoundingClientRect().height > 300);
  const r = footer.getBoundingClientRect();
  return JSON.stringify({ y: window.scrollY, fy: Math.round(r.y * 10) / 10, sh: document.documentElement.scrollHeight, ch: document.documentElement.clientHeight });
})()
""";
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final outDir = args.length > 1 ? args[1] : '/tmp/arxa-compare/par';
  final tag = args.length > 2 ? args[2] : 'mech';
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

    final mech = await tab.evaluate(_mechJs());
    result['mech'] = jsonDecode(mech is String ? mech : jsonEncode(mech));

    if (args.length > 5 && args[5] == 'scroll') {
      final samples = <Map<String, dynamic>>[];
      for (final frac in [-1200.0, -600.0, -300.0, 0.0]) {
        await tab.evaluate(r"(() => { window.scrollTo(0, document.body.scrollHeight); return 1; })()");
        await Future.delayed(const Duration(milliseconds: 700));
        await tab.evaluate('(() => { const m = document.documentElement.scrollHeight - document.documentElement.clientHeight; window.scrollTo(0, m + $frac); return 1; })()');
        await Future.delayed(const Duration(milliseconds: 450));
        final s = await tab.evaluate(_sampleJs());
        samples.add(jsonDecode(s is String ? s : jsonEncode(s)) as Map<String, dynamic>);
      }
      result['samples'] = samples;
    }
    File(outDir + '/' + tag + '-mech.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('mech ok -> ' + outDir + '/' + tag + '-mech.json');
  } finally {
    await client.close();
  }
}
