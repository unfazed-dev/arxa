// appbox lens capture driver: screenshot a URL to a PNG at a given viewport.
// The shell entry point for appboxd/lib/lens.dart until `appbox lens` lands.
// Usage: dart run tool/lens_shot.dart <url> <out.png> [width] [height] [settleMs]
import 'dart:io';

import 'package:appboxd/lens.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 2) {
    stderr.writeln(
        'usage: dart run tool/lens_shot.dart <url> <out.png> [width] [height] [settleMs]');
    exit(2);
  }
  final url = argv[0];
  final out = argv[1];
  final width = argv.length > 2 ? int.parse(argv[2]) : 1280;
  final height = argv.length > 3 ? int.parse(argv[3]) : 800;
  final settleMs = argv.length > 4 ? int.parse(argv[4]) : 1500;
  await captureGolden(url, width, height, goldenPath: out, settleMs: settleMs);
  stdout.writeln('lens shot: $url -> $out (${width}x$height)');
}
