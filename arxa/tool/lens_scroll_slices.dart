// arxa lens scroll-slice driver: capture a URL at successive scroll offsets.
// Extends the lens for pages whose perpetual animation refuses full-page
// stability (LensUnstableCapture): instead of one tall capture, slice the
// scroll height into overlapping viewport stills.
// Usage:
//   dart run tool/lens_scroll_slices.dart <url> <outDir> [width] [height] [settleMs] [stepFrac] [dismissSelector]
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';
import 'package:arxa/lens.dart';
import 'package:arxa/lens/daemon.dart';

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    stderr.writeln(
        'usage: dart run tool/lens_scroll_slices.dart <url> <outDir> '
        '[width] [height] [settleMs] [stepFrac] [dismissSelector]');
    exit(2);
  }
  final url = argv[0];
  final outDir = argv[1];
  final width = argv.length > 2 ? int.parse(argv[2]) : 1280;
  final height = argv.length > 3 ? int.parse(argv[3]) : 832;
  final settleMs = argv.length > 4 ? int.parse(argv[4]) : 7500;
  final stepFrac = argv.length > 5 ? double.parse(argv[5]) : 0.92;
  final dismiss = argv.length > 6 ? argv[6] : '';

  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    // Flat-timer settle on purpose: this driver exists for pages that NEVER
    // converge (perpetual marquees/cursors), so the stability loop is off.
    await tab.navigateAndSettle(url, settleMs: settleMs);
    if (dismiss.isNotEmpty) {
      try {
        final sel = jsonEncode(dismiss);
        await tab.evaluate(
            '(() => { const b = document.querySelector(' + sel + ');'
            ' if (b) b.click(); return !!b; })()');
        await Future.delayed(const Duration(milliseconds: 400));
      } on CdpException {
        // dismiss is best-effort
      }
    }
    final metrics = await tab.evaluate(
        '(() => ({ h: document.documentElement.scrollHeight,'
        ' ih: window.innerHeight }))()') as Map<dynamic, dynamic>;
    final scrollH = (metrics['h'] as num).toInt();
    final innerH = (metrics['ih'] as num).toInt();
    final step = (innerH * stepFrac).round();
    final offsets = <int>[];
    for (var y = 0; y < scrollH - innerH + step; y += step) {
      var capped = y > scrollH - innerH ? scrollH - innerH : y;
      if (capped < 0) capped = 0;
      if (offsets.isNotEmpty && capped == offsets.last) break;
      offsets.add(capped);
    }
    Directory(outDir).createSync(recursive: true);
    final manifest = <Map<String, dynamic>>[];
    for (var i = 0; i < offsets.length; i++) {
      final y = offsets[i];
      // Scroll, then wait for smooth-scroll engines (Lenis) and
      // ScrollTrigger updates to repaint before the still.
      await tab.evaluate(
          'new Promise(r => { window.scrollTo(0, ' + y.toString() + ');'
          ' setTimeout(r, 1000); })');
      final png = await tab.screenshot();
      final name = 'slice_' + i.toString().padLeft(2, '0') + '_y' + y.toString() + '.png';
      File(outDir + '/' + name).writeAsBytesSync(png);
      manifest.add({'i': i, 'y': y, 'file': name});
      stdout.writeln('slice ' + i.toString() + ' @' + y.toString() + ' -> ' + name);
    }
    File(outDir + '/slices.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
      'url': url,
      'width': width,
      'height': height,
      'settleMs': settleMs,
      'scrollHeight': scrollH,
      'innerHeight': innerH,
      'slices': manifest,
    }));
    stdout.writeln('lens scroll-slices: ' + offsets.length.toString() +
        ' slices of scrollHeight ' + scrollH.toString() + ' -> ' + outDir);
  } finally {
    await client.close();
  }
}
