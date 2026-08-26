// CDP spike self-test — proves the Dart CDP-over-WebSocket client can:
//   1. Launch Chrome headless and connect via WS
//   2. Navigate to a page and wait for load
//   3. Set viewport dimensions (device metrics override)
//   4. Extract DOM via Runtime.evaluate (the emit_htmx pattern)
//   5. Capture a screenshot via Page.captureScreenshot (the arxa lens pattern)
//   6. Capture console errors and page errors
//
// This is the risk-first spike from arxa-dart-only-tooling.md §5.
// If this passes, the CDP substrate is proven for both emit_htmx replacement
// and the arxa lens visual gate.

import 'dart:async';
import 'dart:io';

import 'package:arxa/cdp.dart';
import 'package:test/test.dart';

/// Boots a tiny HTTP server serving a known HTML page.
/// Returns the base URL. Call server.close() when done.
Future<(HttpServer, String)> bootTestServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';

  server.listen((req) {
    if (req.uri.path == '/') {
      req.response.headers.contentType = ContentType.html;
      req.response.write('''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>CDP Test</title></head>
<body>
  <div class="phone-screen" data-screen-label="test · screen-1">
    <h1>Hello CDP</h1>
    <p class="content">Extracted via Runtime.evaluate</p>
    <script>console.log('info: normal log');</script>
    <script>console.error('boom: error log');</script>
  </div>
</body>
</html>
''');
      req.response.close();
    } else {
      req.response.statusCode = 404;
      req.response.close();
    }
  });

  return (server, base);
}

void main() {
  group('CdpClient', () {
    late CdpClient client;
    late HttpServer testServer;
    late String baseUrl;

    setUp(() async {
      (testServer, baseUrl) = await bootTestServer();
      client = await CdpClient.launch();
    });

    tearDown(() async {
      await client.close();
      await testServer.close();
    });

    test('launches Chrome and connects via WebSocket', () {
      // If we got here without throwing, the launch + WS connect succeeded.
      expect(client, isNotNull);
    });

    test('navigates, sets viewport, and extracts DOM', () async {
      final tab = await client.newTab();
      await tab.enable();

      await tab.setViewport(390, 844);
      await tab.navigateAndSettle('$baseUrl/', settleMs: 500);

      // Extract the .phone-screen subtree — same pattern as emit_htmx EXTRACT_JS.
      final html = await tab.evaluate('''
        (() => {
          const root = document.querySelector('.phone-screen');
          if (!root) return { ok: false, error: 'no .phone-screen' };
          return { ok: true, html: root.outerHTML };
        })()
      ''');

      expect(html, isA<Map>());
      expect(html['ok'], isTrue);
      expect(html['html'], contains('Hello CDP'));
      expect(html['html'], contains('phone-screen'));
    });

    test('captures a screenshot of the correct dimensions', () async {
      final tab = await client.newTab();
      await tab.enable();
      await tab.setViewport(390, 844);
      await tab.navigateAndSettle('$baseUrl/', settleMs: 500);

      final png = await tab.screenshot();

      // Verify it's a valid PNG (magic bytes: 89 50 4E 47 0D 0A 1A 0A).
      expect(png.length, greaterThan(100), reason: 'screenshot too small');
      expect(png[0], 0x89);
      expect(png[1], 0x50); // P
      expect(png[2], 0x4E); // N
      expect(png[3], 0x47); // G

      // Parse PNG IHDR to verify dimensions (bytes 16-23: width + height big-endian).
      final width = (png[16] << 24) | (png[17] << 16) | (png[18] << 8) | png[19];
      final height = (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23];
      expect(width, 390, reason: 'screenshot width should match viewport');
      expect(height, 844, reason: 'screenshot height should match viewport');
    });

    test('captures console errors and page errors', () async {
      final tab = await client.newTab();
      await tab.enable();
      await tab.navigateAndSettle('$baseUrl/', settleMs: 500);

      // The test page logs console.error('boom: error log').
      expect(tab.consoleErrors, isNotEmpty);
      expect(tab.consoleErrors.any((e) => e.contains('boom')), isTrue);
    });

    test('evaluateFunction passes structured argument (emit_htmx pattern)', () async {
      final tab = await client.newTab();
      await tab.enable();
      await tab.navigateAndSettle('$baseUrl/', settleMs: 500);

      // This is the exact pattern emit_htmx uses:
      // pg.evaluate(EXTRACT_JS, {"root": CONTENT_ROOT, "selectors": selectors, ...})
      final result = await tab.evaluateFunction('''
        (args) => {
          const root = document.querySelector(args.root);
          if (!root) return { ok: false, error: 'no root for ' + args.root };
          for (const sel of (args.selectors || [])) {
            root.querySelectorAll(sel).forEach(el => el.remove());
          }
          return {
            ok: true,
            html: root.outerHTML,
            label: root.getAttribute('data-screen-label'),
          };
        }
      ''', {
        'root': '.phone-screen',
        'selectors': ['script'],
      });

      expect(result['ok'], isTrue);
      expect(result['html'], contains('Hello CDP'));
      // Scripts should have been removed (selectors=['script']).
      expect(result['html'], isNot(contains('<script')));
      expect(result['label'], 'test · screen-1');
    });

    test('multiple tabs are isolated', () async {
      final tab1 = await client.newTab();
      await tab1.enable();
      await tab1.setViewport(390, 844);
      await tab1.navigateAndSettle('$baseUrl/', settleMs: 300);

      final tab2 = await client.newTab();
      await tab2.enable();
      await tab2.setViewport(1280, 800);
      await tab2.navigate('about:blank');

      // tab1 should still have the content.
      final html = await tab1.evaluate('document.querySelector(".phone-screen")?.outerHTML');
      expect(html, isNotNull);

      // tab2 should not have .phone-screen.
      final blank = await tab2.evaluate('document.querySelector(".phone-screen")?.outerHTML');
      expect(blank, isNull);
    });
  });

  // Skip in CI — requires Chrome installed.
  group('CdpClient defaultChromePath', () {
    test('returns a path on macOS', () {
      if (!Platform.isMacOS) return;
      final p = CdpClient.defaultChromePath();
      expect(p, contains('Chrome'));
    }, testOn: 'mac-os');
  });
}
