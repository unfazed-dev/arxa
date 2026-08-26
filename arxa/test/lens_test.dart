// arxa lens test — proves the visual gate can capture, store, and compare.

import 'dart:async';
import 'dart:io';

import 'package:arxa/lens.dart';
import 'package:test/test.dart';

/// Boots a tiny HTTP server serving a colored page.
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

void main() {
  group('Lens', () {
    late HttpServer server;
    late String baseUrl;
    late Directory goldenDir;

    setUp(() async {
      goldenDir = Directory.systemTemp.createTempSync('lens-golden-');
    });

    tearDown(() async {
      await server.close();
      goldenDir.deleteSync(recursive: true);
    });

    test('capture + byte-compare identical page passes', () async {
      (server, baseUrl) = await bootColorServer('#ff0000');
      final goldenPath = '${goldenDir.path}/red.png';

      // Capture golden.
      final golden = await captureGolden(
        '$baseUrl/', 390, 844,
        goldenPath: goldenPath,
        settleMs: 300,
      );
      expect(golden.length, greaterThan(100));
      expect(File(goldenPath).existsSync(), isTrue);

      await server.close();
      (server, baseUrl) = await bootColorServer('#ff0000');

      // Compare identical page.
      final result = await compareGolden(
        '$baseUrl/', goldenPath, 390, 844,
        mode: LensMode.byte,
        settleMs: 300,
      );
      expect(result.passed, isTrue, reason: result.note ?? '');
    });

    test('byte-compare different page fails', () async {
      (server, baseUrl) = await bootColorServer('#00ff00');
      final goldenPath = '${goldenDir.path}/green.png';

      await captureGolden('$baseUrl/', 390, 844, goldenPath: goldenPath, settleMs: 300);
      await server.close();

      (server, baseUrl) = await bootColorServer('#ff0000');
      final result = await compareGolden(
        '$baseUrl/', goldenPath, 390, 844,
        mode: LensMode.byte,
        settleMs: 300,
      );
      expect(result.passed, isFalse);
      expect(result.note, contains('differ'));
    });

    test('missing golden fails with clear message', () async {
      (server, baseUrl) = await bootColorServer('#0000ff');
      final result = await compareGolden(
        '$baseUrl/', '${goldenDir.path}/nonexistent.png', 390, 844,
        settleMs: 300,
      );
      expect(result.passed, isFalse);
      expect(result.note, contains('no golden'));
    });

    test('console error causes lens failure', () async {
      final server2 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base2 = 'http://${server2.address.address}:${server2.port}';
      server2.listen((req) {
        req.response.headers.contentType = ContentType.html;
        req.response.write('''
<!DOCTYPE html><html><head></head><body>
<script>console.error('lens test error');</script>
</body></html>
''');
        req.response.close();
      });

      final goldenPath = '${goldenDir.path}/error.png';
      // First capture the golden (which also has the error, but we save anyway)
      await captureGolden('$base2/', 390, 844, goldenPath: goldenPath, settleMs: 300);

      final result = await compareGolden(
        '$base2/', goldenPath, 390, 844,
        mode: LensMode.byte,
        settleMs: 300,
      );
      // The console error should fail the lens regardless of byte match.
      expect(result.passed, isFalse);
      expect(result.note, anyOf(contains('error'), contains('differ')));
      await server2.close();
    });
  });
}
