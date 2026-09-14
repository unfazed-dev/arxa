// lens_probe_mail_paint.dart — PAINT test for the mail pill's transform.
// Shows the pill statically at a known spot with rotate(10deg) in three
// states: A = filled copyTooltipIn (runtime-identical), B = animation none,
// C = rotate(0) control. Screenshots decide whether the rotation paints.
// Usage: dart run tool/lens_probe_mail_paint.dart <url> <outDir> <tag> [w] [h]
import 'dart:convert';
import 'dart:io';

import 'package:arxa/lens/daemon.dart';

String _revealJs() {
  return """
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

String _showAtJs(String deg, bool killAnim) {
  final kill = killAnim ? "p.style.animation = 'none';" : "p.style.animation = '';";
  return """
(() => {
  let p = [...document.querySelectorAll('div')].find(d => d.classList.contains('mail-pill'));
  if (!p) {
    p = document.createElement('div');
    p.className = 'mail-pill';
    p.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg><span>Copy our email</span>';
    document.body.appendChild(p);
  }
  $kill
  p.setAttribute('data-on', 'true');
  p.style.left = '600px';
  p.style.top = '400px';
  p.style.transform = 'translate(-50%, -50%) rotate($deg)';
  const cs = getComputedStyle(p);
  return JSON.stringify({ style: p.style.transform, comp: cs.transform, anim: cs.animationName, scale: cs.scale, display: cs.display });
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
  final tag = args.length > 2 ? args[2] : 'mail-ours';
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

    // PASS A: rotate(10deg) + filled copyTooltipIn (runtime-identical)
    result['a'] = _jd(await tab.evaluate(_showAtJs('10deg', false)));
    await Future.delayed(const Duration(milliseconds: 600));
    File(outDir + '/' + tag + '-paint-A.png').writeAsBytesSync(await tab.screenshot());

    // PASS B: rotate(10deg), animation killed
    result['b'] = _jd(await tab.evaluate(_showAtJs('10deg', true)));
    await Future.delayed(const Duration(milliseconds: 100));
    File(outDir + '/' + tag + '-paint-B.png').writeAsBytesSync(await tab.screenshot());

    // PASS C: rotate(0) control
    result['c'] = _jd(await tab.evaluate(_showAtJs('0deg', true)));
    await Future.delayed(const Duration(milliseconds: 100));
    File(outDir + '/' + tag + '-paint-C.png').writeAsBytesSync(await tab.screenshot());

    File(outDir + '/' + tag + '-paint.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('paint ok -> ' + outDir + '/' + tag + '-paint.json');
  } finally {
    await client.close();
  }
}
