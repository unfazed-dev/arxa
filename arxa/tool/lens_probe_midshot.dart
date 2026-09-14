// lens_probe_midshot.dart — screenshot at an absolute scrollY (mid-page
// cover check: the pinned footer must not paint over content mid-scroll).
// Usage: dart run tool/lens_probe_midshot.dart <url> <out.png> <scrollY> [w] [h]
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

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final out = args.length > 1 ? args[1] : '/tmp/arxa-compare/par/mid.png';
  final scrollY = args.length > 2 ? double.parse(args[2]) : 6000.0;
  final w = args.length > 3 ? int.parse(args[3]) : 1713;
  final h = args.length > 4 ? int.parse(args[4]) : 1098;
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
    await tab.evaluate('(() => { window.scrollTo(0, $scrollY); return window.scrollY; })()');
    await Future.delayed(const Duration(milliseconds: 900));
    File(out).writeAsBytesSync(await tab.screenshot());
    stdout.writeln('midshot ok ' + out);
  } finally {
    await client.close();
  }
}
