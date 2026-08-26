// arxa lens check driver: navigate, assert, optionally drive input,
// screenshot. Console/page errors are always a failure (lens doctrine).
// Usage: dart run tool/lens_check.dart <url> <out.png> [width] [height] [settleMs]
//        [--selector=<css>] [--press=<Key>]... [--expect=<js-expr>]
import 'dart:io';

import 'package:arxa/cdp.dart';

String? _flag(List<String> argv, String name) {
  final hit = argv.where((a) => a.startsWith('--$name='));
  return hit.isEmpty ? null : hit.first.substring(name.length + 3);
}

String _js(String s) => "'${s.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'";

Future<void> main(List<String> argv) async {
  final positional = argv.where((a) => !a.startsWith('--')).toList();
  if (positional.length < 2) {
    stderr.writeln(
        'usage: dart run tool/lens_check.dart <url> <out.png> [width] [height] [settleMs] '
        '[--selector=<css>] [--press=<Key>]... [--expect=<js-expr>]');
    exit(2);
  }
  final url = positional[0];
  final out = positional[1];
  final width = positional.length > 2 ? int.parse(positional[2]) : 1280;
  final height = positional.length > 3 ? int.parse(positional[3]) : 800;
  final settleMs = positional.length > 4 ? int.parse(positional[4]) : 1500;
  final selector = _flag(argv, 'selector');
  final presses = argv
      .where((a) => a.startsWith('--press='))
      .map((a) => a.substring('--press='.length))
      .toList();
  final expect = _flag(argv, 'expect');

  final failures = <String>[];
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: settleMs);

    if (selector != null) {
      final found = await tab.evaluate('!!document.querySelector(${_js(selector)})');
      if (found != true) failures.add('selector not found: $selector');
    }
    for (final k in presses) {
      await tab.key(k);
      await Future.delayed(const Duration(milliseconds: 250));
    }
    if (presses.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (expect != null) {
      final ok = await tab.evaluate(expect);
      if (ok != true) failures.add('expect not truthy: $expect (got $ok)');
    }
    final errors = [...tab.consoleErrors, ...tab.pageErrors];
    if (errors.isNotEmpty) {
      failures.add('${errors.length} console/page error(s): ${errors.first}');
    }
    final png = await tab.screenshot();
    final f = File(out);
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(png);
  } finally {
    await client.close();
  }
  if (failures.isNotEmpty) {
    stderr.writeln('lens check FAILED: $url\n  ${failures.join('\n  ')}');
    exit(1);
  }
  stdout.writeln('lens check ok: $url -> $out (${width}x$height)');
}
