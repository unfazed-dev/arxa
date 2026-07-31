// Tests for emit_playground — ported helpers (pure, no Chrome) + a CDP
// extraction smoke test (requires Chrome, same pattern as emit_htmx_test.dart
// and cdp_test.dart).
//
// The full pipeline test (serve the design/new playground, read
// window.P2.registry, render every surface, write-on-diff) requires the real
// playground tree and is not covered here.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appboxd/cdp.dart';
import 'package:appboxd/emit_playground.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Boots a tiny HTTP server serving a page that mimics the playground's
/// iPhone-frame layout: .phone-screen root inside .stage chrome, with chrome
/// elements inside the root that the exclusions must strip.
Future<(HttpServer, String)> bootTestServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';

  server.listen((req) {
    if (req.uri.path == '/' || req.uri.path == '/new/index.html') {
      req.response.headers.contentType = ContentType.html;
      req.response.write('''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Playground Test</title></head>
<body>
  <div class="stage">
    <nav class="toolbar">stage chrome — must not appear in extraction</nav>
    <div class="phone">
      <div class="phone-screen">
        <div class="t-hud"><span>HUD overlay</span></div>
        <div class="statusbar"><span class="num">9:41</span></div>
        <div class="fx-content">
          <h1>Extracted Content</h1>
          <img src="assets/icon.svg" alt="icon" width="16" height="16">
        </div>
      </div>
    </div>
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
  // ── pure helper tests (no Chrome required) ──────────────────────────

  group('stripCssComments', () {
    test('removes single-line /* */ blocks', () {
      expect(stripCssComments('a { color: red } /* tweak */'),
          'a { color: red } ');
    });

    test('removes multi-line /* */ blocks', () {
      expect(stripCssComments('/* multi\nline\ncomment */ body { }'),
          ' body { }');
    });

    test('leaves content without comments untouched', () {
      const css = '.foo { color: red; }';
      expect(stripCssComments(css), css);
    });
  });

  group('rewriteAssets', () {
    test('rewrites double-quoted src/href assets/', () {
      expect(rewriteAssets('src="assets/icon.svg"'),
          'src="../assets/icon.svg"');
      expect(rewriteAssets('href="assets/fonts/f.woff2"'),
          'href="../assets/fonts/f.woff2"');
    });

    test('leaves already-rewritten assets/ untouched', () {
      const text = 'src="../assets/icon.svg"';
      expect(rewriteAssets(text), text);
    });

    test('leaves prose containing assets/ untouched', () {
      const text = 'The assets/ folder holds images.';
      expect(rewriteAssets(text), text);
    });

    test('handles multiple URLs in one block', () {
      final input = '<img src="assets/a.svg">'
          '<link href="assets/b.css">';
      final out = rewriteAssets(input);
      expect(out, contains('src="../assets/a.svg"'));
      expect(out, contains('href="../assets/b.css"'));
      expect(out, isNot(contains('="assets/')));
    });
  });

  group('roleFor', () {
    test('uses entry.roles[0] when present', () {
      expect(roleFor({'roles': ['admin', 'user']}, null), 'admin');
      expect(roleFor({'roles': ['leo']}, null), 'leo');
    });

    test('matches the role whose shells contain the entry shell (dict roles)',
        () {
      final roles = {
        'leo': {'shells': ['studio', 'home']},
        'erika': {'shells': ['admin']},
      };
      expect(roleFor({'shell': 'studio'}, roles), 'leo');
      expect(roleFor({'shell': 'admin'}, roles), 'erika');
    });

    test('handles dict roles where the value is a bare list', () {
      final roles = {'leo': ['studio', 'home'], 'erika': ['admin']};
      expect(roleFor({'shell': 'home'}, roles), 'leo');
    });

    test('handles list-of-{id,shells} roles', () {
      final roles = [
        {'id': 'leo', 'shells': ['studio']},
        {'id': 'erika', 'shells': ['admin']},
      ];
      expect(roleFor({'shell': 'admin'}, roles), 'erika');
    });

    test('falls back to the first role when no shell match', () {
      final roles = {
        'leo': {'shells': ['studio']},
        'erika': {'shells': ['admin']},
      };
      expect(roleFor({'shell': 'unknown'}, roles), 'leo');
    });

    test('returns null when roles is null and entry has no roles list', () {
      expect(roleFor({'shell': 'home'}, null), isNull);
      expect(roleFor({}, null), isNull);
    });
  });

  group('banner', () {
    test('is timestamp-free and names the source screen and role', () {
      final b = banner('train.home', 'felix');
      expect(b, contains('train.home'));
      expect(b, contains('felix'));
      expect(b, contains('do not hand-edit'));
      expect(b, contains('design/new/index.html'));
      expect(b, startsWith('<!--'));
      expect(b, endsWith('-->'));
    });
  });

  group('startStaticServer', () {
    test('serves files and resolves directory index.html', () async {
      final tmp = Directory.systemTemp.createTempSync('emit-pg-static');
      Directory(p.join(tmp.path, 'new')).createSync();
      File(p.join(tmp.path, 'new', 'index.html'))
          .writeAsStringSync('<h1>hello</h1>');
      File(p.join(tmp.path, 'new', 'tokens.css'))
          .writeAsStringSync(':root{}');

      final server = await startStaticServer(tmp.path);
      final port = server.port;

      final fileRes = await HttpClient().getUrl(
        Uri.parse('http://127.0.0.1:$port/new/tokens.css'),
      );
      final fileBody = await fileRes
          .close()
          .then((r) => r.transform(utf8.decoder).join());
      expect(fileBody, ':root{}');

      // Directory request resolves to index.html.
      final dirRes = await HttpClient().getUrl(
        Uri.parse('http://127.0.0.1:$port/new/'),
      );
      final dirBody = await dirRes
          .close()
          .then((r) => r.transform(utf8.decoder).join());
      expect(dirBody, '<h1>hello</h1>');

      // Missing file → 404.
      final missRes = await HttpClient().getUrl(
        Uri.parse('http://127.0.0.1:$port/new/missing.txt'),
      );
      final missClose = await missRes.close();
      expect(missClose.statusCode, 404);

      await server.close(force: true);
      tmp.deleteSync(recursive: true);
    });
  });

  group('stopStaticServer', () {
    test('handles null gracefully', () async {
      await stopStaticServer(null); // must not throw
    });
  });

  // ── CDP extraction smoke test (requires Chrome) ─────────────────────
  //
  // Mirrors emit_htmx_test.dart's pattern but uses the exact emit_playground
  // constants (extractJs, contentRoot) to verify the extraction pipeline.

  group('emit_playground CDP extraction', () {
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

    test('EXTRACT_JS extracts .phone-screen and strips exclusion selectors',
        () async {
      final tab = await client.newTab();
      await tab.enable();
      await tab.setViewport(390, 844, mobile: true);
      await tab.navigateAndSettle('$baseUrl/', settleMs: 500);

      final result = await tab.evaluateFunction(extractJs, {
        'root': contentRoot,
        'selectors': ['.t-hud', '.statusbar'],
      });

      expect(result['ok'], isTrue);
      expect(result['html'], contains('Extracted Content'));
      expect(result['html'], contains('phone-screen'));

      // Chrome inside .phone-screen stripped via selectors.
      expect(result['html'], isNot(contains('t-hud')));
      expect(result['html'], isNot(contains('statusbar')));
      expect(result['html'], isNot(contains('9:41')));

      // Chrome outside .phone-screen never enters the extraction.
      expect(result['html'], isNot(contains('toolbar')));
    });

    test('rewriteAssets on extracted content produces ../assets/ URLs',
        () async {
      final tab = await client.newTab();
      await tab.enable();
      await tab.navigateAndSettle('$baseUrl/', settleMs: 500);

      final result = await tab.evaluateFunction(extractJs, {
        'root': contentRoot,
        'selectors': ['.t-hud', '.statusbar'],
      });

      final content = rewriteAssets(result['html'] as String);
      expect(content, contains('src="../assets/icon.svg"'));
      expect(content, isNot(contains('="assets/')));
    });

    test('full doc composition produces valid standalone HTML', () async {
      final tab = await client.newTab();
      await tab.enable();
      await tab.navigateAndSettle('$baseUrl/', settleMs: 500);

      final result = await tab.evaluateFunction(extractJs, {
        'root': contentRoot,
        'selectors': ['.t-hud', '.statusbar'],
      });

      final content = rewriteAssets(result['html'] as String);
      final doc = docTemplate
          .replaceAll('__BANNER__', banner('screen-1', 'felix'))
          .replaceAll('__SURFACE__', 'test_view')
          .replaceAll('__TOKENS__', ':root { --ink: black; }')
          .replaceAll('__APPCSS__', '.card { padding: 8px; }')
          .replaceAll('__CONTENT__', content);

      expect(doc, startsWith('<!DOCTYPE html>'));
      expect(doc, contains('<html lang="en">'));
      expect(doc, contains('GENERATED by appbox_kit/tools/emit_playground'));
      expect(doc, contains('screen-1'));
      expect(doc, contains('Extracted Content'));
      expect(doc, contains(':root { --ink: black; }'));
      expect(doc, contains('.card { padding: 8px; }'));
      expect(doc, endsWith('</html>\n'));
    });
  });
}
