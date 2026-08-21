// Lens gate test — design-vs-built as a pipeline gate.
//
// Covers the contract from plan Task 12:
//   (a) matching goldens pass + write evidence PNGs + leave SARIF clean
//   (b) a mismatched render fails with a ✗ detail naming the surface + its SSIM
//   (c) a console error fails regardless of pixels
//   (d) no `lens` config block → env-skip (exit 2, skipped not failed)
//   (e) recaptureGoldens rewrites the goldens
//
// The web/CDP path is exercised (capture.kind: same) — the same path the lens
// facade's compareGolden already proves in lens_test.dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appboxd/gate_lens.dart';
import 'package:appboxd/gates.dart';
import 'package:test/test.dart';

/// Boots a tiny HTTP server serving a solid-color page at viewport size.
Future<(HttpServer, String)> bootColorServer(String color) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  server.listen((req) {
    req.response.headers.contentType = ContentType.html;
    req.response.write('''
<!DOCTYPE html><html><head><style>
body { margin:0; background:$color; width:390px; height:844px; }
</style></head><body></body></html>
''');
    req.response.close();
  });
  return (server, base);
}

/// Boots a server whose page logs a console error (quality signal).
Future<(HttpServer, String)> bootConsoleErrorServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  server.listen((req) {
    req.response.headers.contentType = ContentType.html;
    req.response.write('''
<!DOCTYPE html><html><head><style>
body { margin:0; background:#0000ff; width:390px; height:844px; }
</style></head><body>
<script>console.error('lens gate test error');</script>
</body></html>
''');
    req.response.close();
  });
  return (server, base);
}

void main() {
  late Directory tmp;
  late HttpServer server;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gate-lens-test-');
  });

  tearDown(() async {
    await server.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('(a) matching goldens pass, write evidence, SARIF stays clean', () async {
    final (s, base) = await bootColorServer('#ff0000');
    server = s;
    writeLensConfig(tmp, base);
    final ctx = GateContext(repoRoot: tmp.path);

    // Seed the golden from the fixture, then compare the same render.
    final seed = await lensGate(ctx, recaptureGoldens: true);
    expect(seed.passed, isTrue, reason: seed.details.join('\n'));

    final r = await lensGate(ctx);
    expect(r.passed, isTrue, reason: r.details.join('\n'));
    expect(r.exitCode, passExit);
    expect(File('${ctx.designRoot}/evidence/lens-gate/home-390.png').existsSync(),
        isTrue,
        reason: 'evidence PNG must be written per compared surface');
    expect(ctx.sarif.results, isEmpty, reason: 'a passing gate emits no SARIF');
  });

  test('(b) mismatched render fails naming the surface + SSIM score', () async {
    final (s1, base1) = await bootColorServer('#ff0000');
    server = s1;
    writeLensConfig(tmp, base1);
    final ctx = GateContext(repoRoot: tmp.path);
    await lensGate(ctx, recaptureGoldens: true);

    // Swap the fixture color and rebind (new port) — the built side moved.
    await server.close();
    final (s2, base2) = await bootColorServer('#00ff00');
    server = s2;
    writeLensConfig(tmp, base2);

    final r = await lensGate(ctx);
    expect(r.passed, isFalse);
    expect(r.exitCode, failExit);
    expect(r.details.any((d) => d.contains('home@390')), isTrue,
        reason: 'the failing detail must name the surface@viewport');
    expect(r.details.any((d) => d.toUpperCase().contains('SSIM')), isTrue,
        reason: 'the failing detail must carry the SSIM score');
  });

  test('(c) console error fails regardless of pixels', () async {
    final (s, base) = await bootConsoleErrorServer();
    server = s;
    writeLensConfig(tmp, base);
    final ctx = GateContext(repoRoot: tmp.path);
    await lensGate(ctx, recaptureGoldens: true);

    final r = await lensGate(ctx);
    expect(r.passed, isFalse, reason: r.details.join('\n'));
  });

  test('(d) no lens config block -> env-skip (exit 2, not a failure)', () async {
    writeConfig(tmp, lens: false);
    final (s, _) = await bootColorServer('#ff0000'); // tearDown closes a server
    server = s;
    final ctx = GateContext(repoRoot: tmp.path);

    final r = await lensGate(ctx);
    expect(r.exitCode, envExit);
    expect(r.passed, isFalse);
  });

  test('(e) recaptureGoldens rewrites the goldens', () async {
    final (s, base) = await bootColorServer('#ff0000');
    server = s;
    writeLensConfig(tmp, base);
    final ctx = GateContext(repoRoot: tmp.path);

    final r = await lensGate(ctx, recaptureGoldens: true);
    expect(r.passed, isTrue);
    expect(File('${ctx.designRoot}/goldens/home-390.png').existsSync(), isTrue);
  });

  test('(f) recapture REFUSES an unreproducible surface, fails, and leaves the '
      'existing golden untouched', () async {
    final (s, base) = await bootNeverSettlesServer();
    server = s;
    writeLensConfig(tmp, base);
    final ctx = GateContext(repoRoot: tmp.path);

    // Seed a golden so the refusal has something to protect. If recapture
    // overwrote it with a frame of a moving page, every later run would compare
    // against a reference that was never reproducible.
    final golden = File('${ctx.designRoot}/goldens/home-390.png');
    golden.parent.createSync(recursive: true);
    golden.writeAsBytesSync([1, 2, 3, 4]);

    final r = await lensGate(ctx, recaptureGoldens: true);

    // FAIL, not ok-with-a-note: the operator's next move is `git add goldens/`,
    // and a green "RECAPTURED" that silently skipped a surface is exactly the
    // false pass this project keeps shipping.
    expect(r.passed, isFalse);
    expect(r.summary, contains('RECAPTURE INCOMPLETE'));
    expect(r.details.join('\n'), contains('REFUSED'));
    expect(golden.readAsBytesSync(), [1, 2, 3, 4],
        reason: 'the pre-existing golden must be byte-untouched');

    // Not an uncaught throw escaping the gate: the gate contract is
    // 0 pass / 1 fail / 2 not-applicable, and a Dart exception would exit 255.
    // Reaching this line at all is that assertion.
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// A page nothing can freeze: `setInterval` repainting text is not a WAAPI
/// animation, so `getAnimations()` cannot see it. Stands in for an animated
/// GIF/APNG, which have no pause API at all.
Future<(HttpServer, String)> bootNeverSettlesServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  server.listen((req) {
    req.response.headers.contentType = ContentType.html;
    req.response.headers.set('cache-control', 'no-store');
    req.response.write('''
<!DOCTYPE html><html><head><style>
body { margin:0; background:#fff; width:390px; height:844px; font:40px monospace; }
</style></head><body><div id="t">0</div>
<script>var n=0;setInterval(function(){
  document.getElementById('t').textContent=String(++n);},80);</script>
</body></html>
''');
    req.response.close();
  });
  return (server, base);
}

/// Write config/appbox.config.json into [tmp]. When [lens] is true, carries a
/// `lens` block pointing at [base]; otherwise omits it (the env-skip case).
void writeLensConfig(Directory tmp, String base) =>
    writeConfig(tmp, lens: true, base: base);

void writeConfig(Directory tmp, {required bool lens, String? base}) {
  final cfg = <String, dynamic>{
    'targets': ['web'],
    'viewports': {
      'mobile': {'width': 390, 'height': 844},
    },
  };
  if (lens && base != null) {
    cfg['lens'] = {
      'goldens': '${GateContext.studioDesignDir}/goldens',
      'surfaces': {'home': '/'},
      'serve': {'kind': 'url', 'base': base},
      'capture': {'kind': 'same', 'settleMs': 300},
      'modes': {'compare': 'ssim', 'threshold': 0.98},
    };
  }
  Directory('${tmp.path}/config').createSync(recursive: true);
  File('${tmp.path}/config/appbox.config.json')
      .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cfg)}\n');
}
