// png_diff.dart — pixel diff of two PNGs (evidence tooling). Prints the
// diff-pixel percentage and optionally writes a red-marked diff image.
// Usage: dart run tool/png_diff.dart a.png b.png [out-diff.png] [tolerance]
import 'dart:io';
import 'package:appboxd/lens/pixels.dart';
import 'package:image/image.dart' as img;

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: png_diff a.png b.png [out-diff.png] [tolerance]');
    exit(64);
  }
  final a = decodePng(await File(args[0]).readAsBytes());
  final b = decodePng(await File(args[1]).readAsBytes());
  final tol = args.length > 3 ? int.parse(args[3]) : 0;
  final d = pixelDiff(a, b, tolerance: tol);
  final pct = (100 * d.diffPixels / d.totalPixels);
  stdout.writeln('${pct.toStringAsFixed(2)}% (${d.diffPixels}/${d.totalPixels}px, tol=$tol)');
  if (args.length > 2 && d.diffImage != null) {
    await File(args[2]).writeAsBytes(img.encodePng(d.diffImage!));
  }
}
