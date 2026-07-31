// lens_cli dispatcher tests — argv routing, exit codes, and artifacts.
//
// Two layers: (a) deterministic dispatcher/pure-verb tests (no Chrome), and
// (b) one Chrome-driven group that drives `shot`/`tokens`/`compare` against an
// ephemeral color server (mirrors lens_test.dart's proven harness). The lens
// modules themselves have their own module tests; this file proves the
// argv→lib WIRING, not the capture internals. Plan: appbox-lens-full-port.md,
// Task 7.1.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appboxd/lens_cli.dart';
import 'package:test/test.dart';

/// Boots a tiny HTTP server serving a colored page (lens_test.dart's harness).
Future<(HttpServer, String)> _bootColorServer(String color) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  server.listen((req) {
    req.response.headers.contentType = ContentType.html;
    req.response.write('<!DOCTYPE html><html><head><style>'
        'body{margin:0;background:$color;width:390px;height:844px}'
        '</style></head><body></body></html>');
    req.response.close();
  });
  return (server, base);
}

void main() {
  group('dispatcher (no Chrome)', () {
    test('--help returns 0', () async {
      expect(await runLensCli(['--help']), 0);
      expect(await runLensCli(['-h']), 0);
    });

    test('empty args returns 2', () async {
      expect(await runLensCli([]), 2);
    });

    test('--self-test returns 0', () async {
      expect(await runLensCli(['--self-test']), 0);
    });

    test('unknown verb returns 2', () async {
      expect(await runLensCli(['bogus-verb']), 2);
    });

    test('shot with too few args returns 2', () async {
      expect(await runLensCli(['shot', 'http://x.test']), 2);
    });

    test('skeleton-diff with too few args returns 2', () async {
      expect(await runLensCli(['skeleton-diff', 'a.json']), 2);
    });

    test('compare with too few args returns 2', () async {
      expect(await runLensCli(['compare', 'http://x.test']), 2);
    });
  });

  group('skeleton-diff (pure, no Chrome)', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('lens_cli_skdiff_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    File writeDoc(String name, Map<String, dynamic> doc) {
      final f = File('${tmp.path}/$name');
      f.writeAsStringSync(jsonEncode(doc));
      return f;
    }

    test('identical skeletons pass (exit 0)', () async {
      final sk = {
        'format': 'lens-skeleton/1',
        'nodes': [
          {'id': '#a', 'role': 'banner', 'bbox': [0, 0, 10, 10], 'z': 0}
        ],
      };
      final a = writeDoc('a.json', sk);
      final b = writeDoc('b.json', sk);
      expect(await runLensCli(['skeleton-diff', a.path, b.path]), 0);
    });

    test('differing skeletons fail (exit 1)', () async {
      final aDoc = {
        'nodes': [
          {'id': '#a', 'role': 'banner', 'bbox': [0, 0, 10, 10], 'z': 0}
        ],
      };
      final bDoc = {
        'nodes': [
          {'id': '#a', 'role': 'banner', 'bbox': [0, 0, 10, 10], 'z': 0},
          {'id': '#b', 'role': 'main', 'bbox': [0, 20, 10, 10], 'z': 1}
        ],
      };
      final a = writeDoc('a.json', aDoc);
      final b = writeDoc('b.json', bDoc);
      expect(await runLensCli(['skeleton-diff', a.path, b.path]), 1);
    });
  });

  group('native flutter parse-uri (pure, no connection)', () {
    test('extracts the wsUri from an app.debugPort event line', () async {
      // Drive through a temp file so the verb reads from disk like a real run.
      final tmp = Directory.systemTemp.createTempSync('lens_cli_vm_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final f = File('${tmp.path}/out.txt');
      f.writeAsStringSync(
          '{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:12345/abc/"}}');
      expect(await runLensCli(['native', 'flutter', 'parse-uri', f.path]), 0);
    });

    test('no URI in the text fails (exit 1)', () async {
      expect(
          await runLensCli(
              ['native', 'flutter', 'parse-uri', 'nothing here at all']),
          1);
    });
  });

  group('native family routing (no toolchain)', () {
    test('native with no family returns 2', () async {
      expect(await runLensCli(['native']), 2);
    });

    test('native <unknown> returns 2', () async {
      expect(await runLensCli(['native', 'linux']), 2);
    });

    test('native adb with unknown verb returns 2 (no adb call)', () async {
      expect(await runLensCli(['native', 'adb', 'teleport']), 2);
    });

    test('native macos only supports shot', () async {
      expect(await runLensCli(['native', 'macos', 'record']), 2);
    });
  });

  // One Chrome-driven group — mirrors lens_test.dart's proven color-server
  // harness. Asserts the argv→lib wiring produces the right exit code + file
  // artifact, not the capture internals (those live in lens_test.dart).
  group('wiring vs ephemeral server (Chrome)', () {
    test('shot writes a PNG (exit 0)', () async {
      final (server, base) = await _bootColorServer('#ff0000');
      final out = '${Directory.systemTemp.createTempSync('lens_cli_shot').path}/red.png';
      try {
        final rc = await runLensCli(['shot', '$base/', out, '390', '844', '300']);
        expect(rc, 0, reason: 'shot must succeed on a clean page');
        expect(File(out).existsSync(), isTrue);
        expect(File(out).lengthSync(), greaterThan(100));
      } finally {
        await server.close();
      }
    });

    test('tokens writes certified JSON (exit 0)', () async {
      final (server, base) = await _bootColorServer('#0088ff');
      final out =
          '${Directory.systemTemp.createTempSync('lens_cli_tokens').path}/t.json';
      try {
        final rc = await runLensCli(
            ['tokens', '$base/', '390', '844', '--out=$out', '--settle=300']);
        expect(rc, 0);
        final doc = jsonDecode(File(out).readAsStringSync()) as Map<String, dynamic>;
        expect(doc['certified'], isTrue);
        expect(doc['viewport'], [390, 844]);
      } finally {
        await server.close();
      }
    });

    test('compare identical page passes (exit 0)', () async {
      final (server, base) = await _bootColorServer('#00ff00');
      final golden =
          '${Directory.systemTemp.createTempSync('lens_cli_cmp').path}/g.png';
      try {
        // Capture golden via the shot verb, then compare live against it.
        expect(await runLensCli(['shot', '$base/', golden, '390', '844', '300']), 0);
        expect(
            await runLensCli(
                ['compare', '$base/', golden, '390', '844', '--mode=byte']),
            0);
      } finally {
        await server.close();
      }
    });

    test('compare different page fails (exit 1)', () async {
      var (server, base) = await _bootColorServer('#0000ff');
      final golden =
          '${Directory.systemTemp.createTempSync('lens_cli_cmp2').path}/g.png';
      try {
        expect(await runLensCli(['shot', '$base/', golden, '390', '844', '300']), 0);
        await server.close();
        (server, base) = await _bootColorServer('#ff0000');
        expect(
            await runLensCli(
                ['compare', '$base/', golden, '390', '844', '--mode=byte']),
            1);
      } finally {
        await server.close();
      }
    });
  });
}
