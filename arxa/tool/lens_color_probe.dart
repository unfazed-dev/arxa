// Lens color-fidelity probe (2026-08-25): does Page.captureScreenshot return
// the pixels the page actually specified, or a color-managed washout?
//
// Root cause gated: on wide-gamut hosts (this Mac renders Display P3),
// headless Chrome composites with the host display profile unless told
// otherwise, and untagged sRGB page colors can come back double-transformed
// — lighter, desaturated ("washed"). DOM asserts cannot see this; only
// pixel readback can. Decode goes through the shared substrate
// (lens/pixels.dart) — no second decoder.
//
// Three compositing paths, because they fail independently:
//   1. plain div                 — the ordinary raster path
//   2. will-change:transform div — its own compositing layer
//   3. WebGL canvas              — the GL path (headless SwiftShader)
//
//   dart run tool/lens_color_probe.dart
// Optional A/B: PROBE_EXTRA_ARGS="--flag=value --other" adds Chrome flags.
import 'dart:io';
import 'package:arxa/cdp.dart';
import 'package:arxa/lens.dart';

int fails = 0;
void check(bool ok, String label) {
  stdout.writeln((ok ? 'PASS ' : 'FAIL ') + label);
  if (!ok) fails++;
}

Future<void> main() async {
  final extra = Platform.environment['PROBE_EXTRA_ARGS']
          ?.split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .toList() ??
      const <String>[];
  final client = await CdpClient.launch(extraArgs: extra);
  final tab = await client.newTab();
  await tab.setViewport(800, 600);

  // Three 200px bands: plain, own-layer (will-change), WebGL.
  const dark = [11, 15, 20]; // #0b0f14
  const blue = [47, 107, 255]; // #2f6bff
  const pink = [255, 51, 102]; // #ff3366
  final body = '<!doctype html><html><body style="margin:0">'
      '<div style="height:200px;background:rgb(11,15,20)"></div>'
      '<div style="height:200px;background:rgb(47,107,255);will-change:transform"></div>'
      '<canvas id="c" width="800" height="200" style="display:block"></canvas>'
      '<script>'
      'const c=document.getElementById("c");let kind="failed";'
      'const gl=c.getContext("webgl",{preserveDrawingBuffer:true});'
      'if(gl){gl.clearColor(1,0.2,0.4,1);gl.clear(gl.COLOR_BUFFER_BIT);kind="webgl";}'
      'else{const x=c.getContext("2d");x.fillStyle="rgb(255,51,102)";x.fillRect(0,0,800,200);kind="2d";}'
      'document.title=kind;'
      '</script></body></html>';
  final html = Uri.dataFromString(body, mimeType: 'text/html').toString();

  await tab.navigateAndSettleForCapture(html, settleMs: 900);
  final kind = await tab.evaluate('document.title');
  final img = decodePng(await tab.screenshot());

  check(img.width == 800 && img.height == 600,
      'capture is 800x600 (${img.width}x${img.height})');
  check(kind == 'webgl', 'WebGL context acquired (got "$kind")');

  int maxDelta(List<int> want, List<int> got) {
    var d = 0;
    for (var i = 0; i < 3; i++) {
      final dd = (want[i] - got[i]).abs();
      if (dd > d) d = dd;
    }
    return d;
  }

  void band(String label, int y, List<int> want) {
    final p = img.getPixel(400, y);
    final got = [p.r.toInt(), p.g.toInt(), p.b.toInt()];
    final d = maxDelta(want, got);
    check(d <= 8, '$label rgb(${got.join(",")}) vs rgb(${want.join(",")}) maxD=$d');
  }

  band('plain div    ', 100, dark);
  band('own-layer div', 300, blue);
  band('GL canvas    ', 500, pink);
  if (extra.isNotEmpty) stdout.writeln('flags: ${extra.join(" ")}');
  stdout.writeln(fails == 0 ? 'ALL PROBES PASS' : '$fails PROBES FAILED');
  await client.close();
  exit(fails == 0 ? 0 : 1);
}
