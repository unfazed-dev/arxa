// lens_probe_copytip.dart — real-mouse click on the giant email, frame at
// 300ms (tooltip bubble) + the tip's computed state over time.
// Usage: dart run tool/lens_probe_copytip.dart <url> <outDir> <tag>
import 'dart:convert';
import 'dart:io';
import 'package:arxa/lens/daemon.dart';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final outDir = args.length > 1 ? args[1] : '/tmp/arxa-compare/pf';
  final tag = args.length > 2 ? args[2] : 'tip';
  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1713, 1098);
    await tab.navigateAndSettle(url, settleMs: 700);
    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < 30000) {
      final ok = await tab.evaluate(r"(() => ![...document.querySelectorAll('div')].some(d => { const s = getComputedStyle(d); return s.position === 'fixed' && (s.zIndex === '9999' || s.zIndex === '99999'); }))()");
      if (ok == true) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await Future.delayed(const Duration(milliseconds: 700));
    await tab.evaluate(r"(() => { const btn = [...document.querySelectorAll('button')].find(b => /^(accept)$/i.test((b.textContent || '').trim())); if (btn) btn.click(); return 1; })()");
    await Future.delayed(const Duration(milliseconds: 300));
    await tab.evaluate(r"(() => { window.scrollTo(0, document.body.scrollHeight); return window.scrollY; })()");
    await Future.delayed(const Duration(milliseconds: 1200));
    final pt = await tab.evaluate(r"""
(() => {
  const el = document.querySelector('[data-footer-email]');
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return [r.x + r.width / 2, r.y + Math.min(r.height / 2, 90)];
})()
""");
    final c = (pt is List && pt.length == 2) ? [pt[0] as num, pt[1] as num] : null;
    if (c == null) { stdout.writeln('no email el'); return; }
    await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseMoved', 'x': c[0].toDouble(), 'y': c[1].toDouble() });
    await tab.send('Input.dispatchMouseEvent', { 'type': 'mousePressed', 'x': c[0].toDouble(), 'y': c[1].toDouble(), 'button': 'left', 'clickCount': 1 });
    await tab.send('Input.dispatchMouseEvent', { 'type': 'mouseReleased', 'x': c[0].toDouble(), 'y': c[1].toDouble(), 'button': 'left', 'clickCount': 1 });
    await Future.delayed(const Duration(milliseconds: 300));
    File(outDir + '/' + tag + '-copy-300.png').writeAsBytesSync(await tab.screenshot());
    final st = await tab.evaluate(r"""
(() => {
  const tip = document.querySelector('.footer-copy-tip');
  const box = document.querySelector('[data-footer-email]');
  return JSON.stringify({ isCopied: box.classList.contains('is-copied'), op: getComputedStyle(tip).opacity, scale: getComputedStyle(tip).scale, left: tip.style.left, top: tip.style.top });
})()
""");
    stdout.writeln('tip@300ms: ' + (st is String ? st : jsonEncode(st)));
    await Future.delayed(const Duration(milliseconds: 1400));
    final st2 = await tab.evaluate(r"""
(() => { const tip = document.querySelector('.footer-copy-tip'); const box = document.querySelector('[data-footer-email]'); return JSON.stringify({ isCopied: box.classList.contains('is-copied'), op: getComputedStyle(tip).opacity }); })()
""");
    stdout.writeln('tip@1700ms: ' + (st2 is String ? st2 : jsonEncode(st2)));
  } finally {
    await client.close();
  }
}

