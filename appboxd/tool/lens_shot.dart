// appbox lens capture driver: screenshot a URL to a PNG at a given viewport.
// The shell entry point for appboxd/lib/lens.dart until `appbox lens` lands.
// Usage: dart run tool/lens_shot.dart <url> <out.png> [width] [height] [settleMs] [--full]
//   --full captures beyond the viewport (the whole scroll height).
import 'dart:io';

import 'package:appboxd/lens.dart';

Future<void> main(List<String> argv) async {
  final positional = argv.where((a) => a != '--full').toList();
  final fullPage = argv.length != positional.length;
  if (positional.length < 2) {
    stderr.writeln(
        'usage: dart run tool/lens_shot.dart <url> <out.png> [width] [height] [settleMs] [--full]');
    exit(2);
  }
  final url = positional[0];
  final out = positional[1];
  final width = positional.length > 2 ? int.parse(positional[2]) : 1280;
  final height = positional.length > 3 ? int.parse(positional[3]) : 800;
  final settleMs = positional.length > 4 ? int.parse(positional[4]) : 1500;
  try {
    await captureGolden(url, width, height,
        goldenPath: out, settleMs: settleMs, fullPage: fullPage);
  } on LensUnstableCapture catch (e) {
    // Same catch as `appbox lens shot` in lens_cli.dart. Found by auditing
    // every captureGolden caller after fixing that one — this driver writes a
    // golden too, and an uncaught throw here would exit 255 with a Dart stack
    // trace instead of the 2-is-usage / 1-is-failure convention the rest of
    // this file already follows.
    stderr.writeln('lens shot: FAIL — $e');
    exit(1);
  }
  stdout.writeln(
      'lens shot: $url -> $out (${width}x$height${fullPage ? ', full page' : ''})');
}
