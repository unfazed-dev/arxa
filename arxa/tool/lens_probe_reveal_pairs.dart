// lens_probe_reveal_pairs.dart — capture the reveal itself: scroll to
// maxScroll-offset so the content bottom sits at the same viewport y on both
// sides (section-relative law), then screenshot. Offsets: 402 (early reveal,
// footer bottom rows showing) and 0 (max, full footer).
// Usage: dart run tool/lens_probe_reveal_pairs.dart <url> <outDir> <tag> [w] [h]
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

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final outDir = args.length > 1 ? args[1] : '/tmp/arxa-compare/par';
  final tag = args.length > 2 ? args[2] : 'rv';
  final w = args.length > 3 ? int.parse(args[3]) : 1713;
  final h = args.length > 4 ? int.parse(args[4]) : 1098;
  Directory(outDir).createSync(recursive: true);
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
    await tab.evaluate(r"(() => { window.scrollTo(0, document.body.scrollHeight); return 1; })()");
    await Future.delayed(const Duration(milliseconds: 1500));
    final maxRaw = await tab.evaluate(r"(() => document.documentElement.scrollHeight - document.documentElement.clientHeight)()");
    final maxScroll = (maxRaw is num) ? maxRaw.toDouble() : double.parse(maxRaw.toString());
    for (final offset in [402.0, 0.0]) {
      await tab.evaluate('(() => { window.scrollTo(0, ' + (maxScroll - offset).toString() + '); return window.scrollY; })()');
      await Future.delayed(const Duration(milliseconds: 500));
      File(outDir + '/' + tag + '-reveal-' + offset.round().toString() + '.png').writeAsBytesSync(await tab.screenshot());
    }
    stdout.writeln('reveal pairs ok -> ' + outDir + '/' + tag + '-reveal-*.png max=' + maxScroll.round().toString());
  } finally {
    await client.close();
  }
}
