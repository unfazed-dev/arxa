// lens_probe_layout_dump.dart — dump main's section stack (rects, bottoms)
// to find where the black shell ends vs the footer seam.
// Usage: dart run tool/lens_probe_layout_dump.dart <url> <out> <tag>
import 'dart:convert';
import 'dart:io';
import 'package:arxa/lens/daemon.dart';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final out = args.length > 1 ? '/tmp/arxa-compare/par' : args[1];
  final tag = args.length > 2 ? args[2] : 'dump';
  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1713, 1098);
    await tab.navigateAndSettle(url, settleMs: 700);
    await Future.delayed(const Duration(milliseconds: 1200));
    final js = r"""
(() => {
  const main = document.querySelector('main');
  const secs = [...main.children].map(c => {
    const r = c.getBoundingClientRect(); const cs = getComputedStyle(c);
    return { cls: String(c.className).slice(0, 40), top: Math.round(r.top + window.scrollY), h: Math.round(r.height), bg: cs.backgroundColor.slice(0, 30), pos: cs.position };
  });
  const spacer = document.querySelector('.footer-reveal-spacer');
  const bodyKids = [...document.body.children].map(c => {
    const r = c.getBoundingClientRect(); const cs = getComputedStyle(c);
    return { tag: c.tagName.toLowerCase(), cls: String(c.className).slice(0, 40), top: Math.round(r.top + window.scrollY), h: Math.round(r.height), pos: cs.position, z: cs.zIndex };
  });
  const mcs = getComputedStyle(main);
  return JSON.stringify({ mainH: Math.round(main.getBoundingClientRect().height), mainPos: mcs.position, mainZ: mcs.zIndex, mainBg: mcs.backgroundColor, spacerH: spacer ? spacer.getBoundingClientRect().height : null, sh: document.documentElement.scrollHeight, secs, bodyKids });
})()
""";
    final res = await tab.evaluate(js);
    final decoded = jsonDecode(res is String ? res : jsonEncode(res));
    File(out + '/' + tag + '-layout.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(decoded));
    stdout.writeln('dump ok');
  } finally {
    await client.close();
  }
}
