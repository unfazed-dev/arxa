// lens_dot_svg_check — renders the [data-cursor-dot] native cursor SVG
// (the exact data URL baked into base.css) at 40x upscale on BOTH surface
// poles and samples the tone bands: core center must be the dark tone,
// the annulus white, the outer stroke dark, outside = the page surface.
// Native cursor images never appear in CDP screenshots — this is the only
// way to SEE what the handoff dot actually paints. Usage:
//   dart run tool/lens_dot_svg_check.dart <path/to/base.css>
import 'dart:io';
import 'package:arxa/cdp.dart';
import 'package:arxa/lens/pixels.dart' show decodePng;

Future<void> main(List<String> argv) async {
  final css = await File(argv[0]).readAsString();
  final m = RegExp(r'cursor: url\("data:image/svg\+xml,([^"]+)"\)').firstMatch(css);
  if (m == null) {
    stderr.writeln('NO native dot data URL found in css');
    exit(2);
  }
  final svgUrl = 'data:image/svg+xml,' + m.group(1)!;
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(560, 560);
    for (final bg in ['#ffffff', '#1a1423']) {
      final page = '<body style="margin:0;background:' + bg + '">'
          + '<img src="' + svgUrl + '" width="480" height="480" style="image-rendering:pixelated;margin:40px">'
          + '</body>';
      await tab.navigateAndSettle('data:text/html,' + Uri.encodeComponent(page), settleMs: 1200);
      final png = await tab.screenshot();
      final img = decodePng(png);
      String at(int x, int y) {
        final p = img.getPixel(x, y);
        return '#' + [p.r.toInt(), p.g.toInt(), p.b.toInt()].map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      }
      // img box starts at 40,40; 480px = 12px * 40 scale; center at 280,280
      final rows = {
        'core-r0': at(280, 280),
        'annulus-r3.2': at(280, 280 - 128),
        'stroke-r5': at(280, 280 - 200),
        'outside-r5.9': at(516, 280),
      };
      stdout.writeln('bg=' + bg + '  ' + rows.entries.map((e) => e.key + '=' + e.value).join('  '));
    }
    stdout.writeln('DONE');
  } finally {
    await client.close();
  }
}
