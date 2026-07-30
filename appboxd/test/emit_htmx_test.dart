// Tests for emit_htmx — ported helpers (pure, no Chrome) + a CDP extraction
// smoke test (requires Chrome, same pattern as cdp_test.dart).
//
// The full pipeline test (boot the htmx producer, render every registry
// surface, write-on-diff) requires the real htmx producer tree and is not
// covered here.

import 'dart:async';
import 'dart:io';

import 'package:appboxd/cdp.dart';
import 'package:appboxd/emit_htmx.dart';
import 'package:test/test.dart';

/// Boots a tiny HTTP server serving a page that mimics the htmx producer's
/// stage layout: .phone-screen root inside .phone/.stage chrome, with chrome
/// elements inside the root that the exclusions must strip.
Future<(HttpServer, String)> bootTestServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';

  server.listen((req) {
    if (req.uri.path == '/') {
      req.response.headers.contentType = ContentType.html;
      req.response.write('''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Emit Test</title></head>
<body>
  <div class="stage">
    <nav class="toolbar">stage chrome — must not appear in extraction</nav>
    <div class="phone">
      <div class="phone-screen" data-theme="light" data-screen-label="felix · screen-1">
        <div class="dyn-island"></div>
        <div class="statusbar"><span class="num">9:41</span></div>
        <div class="fx-content">
          <h1>Extracted Content</h1>
          <img src="/assets/icon.svg" alt="icon" width="16" height="16">
          <div class="fx-styled" style="background-image: url(/assets/bg.png)"></div>
        </div>
        <div class="home-ind"></div>
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
    test('rewrites double-quoted attribute URLs', () {
      expect(rewriteAssets('src="/assets/icon.svg"'),
          'src="../assets/icon.svg"');
      expect(rewriteAssets('href="/assets/css/app.css"'),
          'href="../assets/css/app.css"');
    });

    test('rewrites single-quoted attribute URLs', () {
      expect(rewriteAssets("href='/assets/fonts/f.woff2'"),
          "href='../assets/fonts/f.woff2'");
    });

    test('rewrites bare and quoted CSS url()', () {
      expect(rewriteAssets('url(/assets/icon.svg)'),
          'url(../assets/icon.svg)');
      expect(rewriteAssets('url("/assets/icon.svg")'),
          'url("../assets/icon.svg")');
      expect(rewriteAssets("url('/assets/icon.svg')"),
          "url('../assets/icon.svg')");
    });

    test('rewrites srcset list separators', () {
      expect(
        rewriteAssets('srcset="/assets/a.png 1x, /assets/b.png 2x"'),
        'srcset="../assets/a.png 1x, ../assets/b.png 2x"',
      );
    });

    test('leaves prose containing /assets/ untouched', () {
      const text = 'The path /assets/ is absolute and matters.';
      expect(rewriteAssets(text), text);
    });

    test('handles multiple URLs in one block', () {
      final input = '<img src="/assets/a.svg">'
          '<link href="/assets/b.css">'
          '<div style="background: url(/assets/c.png)"></div>';
      final out = rewriteAssets(input);
      expect(out, contains('src="../assets/a.svg"'));
      expect(out, contains('href="../assets/b.css"'));
      expect(out, contains('url(../assets/c.png)'));
      expect(out, isNot(contains('="/assets/')));
    });
  });

  group('roleFor', () {
    test('uses first role when roles list is present', () {
      expect(roleFor({'roles': ['admin', 'user']}), 'admin');
      expect(roleFor({'roles': ['leo']}), 'leo');
    });

    test('derives Studio-* comp → leo', () {
      expect(roleFor({'comp': 'StudioHome'}), 'leo');
    });

    test('derives Admin-* comp → erika', () {
      expect(roleFor({'comp': 'AdminPanel'}), 'erika');
    });

    test('falls back to felix', () {
      expect(roleFor({'comp': 'PlayerTrain'}), 'felix');
      expect(roleFor({}), 'felix');
      expect(roleFor({'comp': null}), 'felix');
    });
  });

  group('assertAssetsRewritten', () {
    test('catches un-rewritten /assets/ URLs', () {
      final failures = <String>[];
      assertAssetsRewritten('test', 'src="/assets/x.svg"', failures);
      expect(failures, isNotEmpty);
      expect(failures.first, contains('un-rewritten'));
    });

    test('passes clean text with rewritten URLs (no surfacesDir)', () {
      final failures = <String>[];
      assertAssetsRewritten('test', 'src="../assets/x.svg"', failures);
      expect(failures, isEmpty);
    });

    test('detects rewritten URLs that do not resolve on disk', () {
      final failures = <String>[];
      assertAssetsRewritten(
        'test',
        'src="../assets/does-not-exist.svg"',
        failures,
        surfacesDir: '/tmp/nonexistent-surfaces-test',
      );
      expect(failures, isNotEmpty);
      expect(failures.first, contains('do not resolve'));
    });

    test('passes rewritten URLs that DO resolve on disk', () {
      // surfacesDir is surfaces/; ../assets/ resolves to the sibling assets/ dir.
      final tmp = Directory.systemTemp.createTempSync('emit-asset-test');
      Directory('${tmp.path}/surfaces').createSync();
      Directory('${tmp.path}/assets').createSync();
      File('${tmp.path}/assets/icon.svg').writeAsStringSync('<svg/>');
      final failures = <String>[];
      assertAssetsRewritten(
        'test',
        'src="../assets/icon.svg"',
        failures,
        surfacesDir: '${tmp.path}/surfaces',
      );
      expect(failures, isEmpty);
      tmp.deleteSync(recursive: true);
    });
  });

  group('banner', () {
    test('is timestamp-free and names the source screen and role', () {
      final b = banner('train.player', 'felix');
      expect(b, contains('train.player'));
      expect(b, contains('felix'));
      expect(b, contains('do not hand-edit'));
      expect(b, startsWith('<!--'));
      expect(b, endsWith('-->'));
    });
  });

  group('freePort', () {
    test('returns a usable ephemeral port', () async {
      final port = await freePort();
      expect(port, greaterThan(0));
      // The port should be bindable (freePort already released it).
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await s.close();
    });
  });

  group('stopServer', () {
    test('handles null gracefully', () async {
      await stopServer(null); // must not throw
    });
  });

  // ── CDP extraction smoke test (requires Chrome) ─────────────────────
  //
  // Mirrors cdp_test.dart's pattern but uses the exact emit_htmx constants
  // (extractJs, contentRoot, placeholderMark) to verify the extraction
  // pipeline that emitHtmx drives.

  group('emit_htmx CDP extraction', () {
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
        'selectors': [
          '.phone',
          '.statusbar',
          '.t-hud',
          '.dyn-island',
          '.home-ind',
        ],
        'placeholderMark': placeholderMark,
      });

      expect(result['ok'], isTrue);
      expect(result['html'], contains('Extracted Content'));
      expect(result['html'], contains('phone-screen'));

      // Chrome inside .phone-screen stripped via selectors.
      expect(result['html'], isNot(contains('dyn-island')));
      expect(result['html'], isNot(contains('statusbar')));
      expect(result['html'], isNot(contains('home-ind')));
      expect(result['html'], isNot(contains('9:41')));

      // Chrome outside .phone-screen never enters the extraction.
      expect(result['html'], isNot(contains('toolbar')));

      expect(result['label'], 'felix · screen-1');
      expect(result['placeholder'], isFalse);
    });

    test('rewriteAssets on extracted content produces clean surface URLs',
        () async {
      final tab = await client.newTab();
      await tab.enable();
      await tab.navigateAndSettle('$baseUrl/', settleMs: 500);

      final result = await tab.evaluateFunction(extractJs, {
        'root': contentRoot,
        'selectors': ['.dyn-island', '.statusbar', '.home-ind'],
        'placeholderMark': placeholderMark,
      });

      final content = rewriteAssets(result['html'] as String);

      // Attribute URLs rewritten.
      expect(content, contains('src="../assets/icon.svg"'));
      // Inline-style url() rewritten.
      expect(content, contains('url(../assets/bg.png)'));
      // No un-rewritten /assets/ URLs survive.
      expect(content, isNot(contains('="/assets/')));
      expect(content, isNot(contains('url(/assets/')));
    });

    test('full doc composition produces valid standalone HTML', () async {
      final tab = await client.newTab();
      await tab.enable();
      await tab.navigateAndSettle('$baseUrl/', settleMs: 500);

      final result = await tab.evaluateFunction(extractJs, {
        'root': contentRoot,
        'selectors': ['.dyn-island', '.statusbar', '.home-ind'],
        'placeholderMark': placeholderMark,
      });

      final content = rewriteAssets(result['html'] as String);
      final doc = docTemplate
          .replaceAll('__BANNER__', banner('screen-1', 'felix'))
          .replaceAll('__SURFACE__', 'test_view')
          .replaceAll('__CSS__', '.token { color: red; }')
          .replaceAll('__CONTENT__', content);

      expect(doc, startsWith('<!DOCTYPE html>'));
      expect(doc, contains('<html lang="en">'));
      expect(doc, contains('GENERATED by appboxd/emit_htmx'));
      expect(doc, contains('screen-1'));
      expect(doc, contains('Extracted Content'));
      expect(doc, contains('.token { color: red; }'));
      expect(doc, endsWith('</html>\n'));
    });
  });
}
