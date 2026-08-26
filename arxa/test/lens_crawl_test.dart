// Multi-route crawl + cross-route token merge.
//
// Exercises crawlSite (seeded + same-origin-discovered routes, robots.txt
// fail-closed, per-route shot/tokens/skeleton, site.json manifest) and
// mergeDesignSystem (ΔE2000 palette clustering into design_system.json).
// robotsAllows is checked directly against the fixture's /robots.txt.
import 'dart:convert';
import 'dart:io';

import 'package:arxa/lens/crawl.dart';
import 'package:arxa/lens/pixels.dart';
import 'package:test/test.dart';

/// Boots an ephemeral server with three routes /a, /b, /c sharing one palette.
/// /a links /b, /c and an external URL; /robots.txt disallows /c. When
/// [serveRobots] is false, /robots.txt 404s (no rules → allow all).
Future<(HttpServer, String)> bootCrawlServer({bool serveRobots = true}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  const shared = '''
    body { background: #ffffff; color: #202124; font-size: 16px; margin: 0; font-family: sans-serif; }
    .btn { background: #1a73e8; color: #ffffff; padding: 8px 16px; border: 0; display: inline-block; }
    h1 { font-size: 24px; }
  ''';
  String page(String title, String body) =>
      '<!DOCTYPE html><html><head><style>$shared</style></head><body>'
      '<h1>$title</h1>$body</body></html>';
  server.listen((req) {
    final path = req.uri.path;
    if (path == '/robots.txt') {
      if (serveRobots) {
        req.response.headers.contentType = ContentType.text;
        req.response.write('User-agent: *\nDisallow: /c\n');
      } else {
        req.response.statusCode = HttpStatus.notFound;
      }
    } else if (path == '/a') {
      req.response.headers.contentType = ContentType.html;
      req.response.write(page(
        'A',
        '<a class="btn" href="/b">to B</a>'
        '<a class="btn" href="/c">to C</a>'
        '<a href="https://example.com/external">external</a>',
      ));
    } else if (path == '/b') {
      req.response.headers.contentType = ContentType.html;
      req.response.write(page('B', '<a class="btn" href="/a">to A</a>'));
    } else if (path == '/c') {
      req.response.headers.contentType = ContentType.html;
      req.response.write(page('C', '<p>disallowed</p>'));
    } else {
      req.response.statusCode = HttpStatus.notFound;
    }
    req.response.close();
  });
  return (server, base);
}

List<int> hexToRgb(String hex) {
  final h = hex.replaceFirst('#', '');
  return [
    int.parse(h.substring(0, 2), radix: 16),
    int.parse(h.substring(2, 4), radix: 16),
    int.parse(h.substring(4, 6), radix: 16),
  ];
}

void main() {
  group('crawlSite', () {
    test('captures seeded + discovered same-origin routes, respects robots', () async {
      final (server, baseUrl) = await bootCrawlServer();
      final tmp = await Directory.systemTemp.createTemp('crawl-test-');
      try {
        final result = await crawlSite(
          baseUrl,
          routes: const ['/a'],
          crawl: true,
          outDir: tmp.path,
          settleMs: 400,
          delayMs: 0,
        );

        // /a (seeded) + /b (discovered) captured; /c robots-disallowed.
        expect(result.routes, containsAll(['/a', '/b']));
        expect(result.routes.length, 2);
        expect(result.routes, isNot(contains('/c')));

        final site = jsonDecode(
          File('${tmp.path}/site.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        final routesList =
            (site['routes'] as List).cast<Map<String, dynamic>>();
        final byRoute = {
          for (final r in routesList) r['route'] as String: r,
        };
        expect(byRoute['/a']!['discovered'], false);
        expect(byRoute['/b']!['discovered'], true);

        final skipped = (site['skipped'] as List).cast<Map<String, dynamic>>();
        expect(
          skipped.any((s) =>
              (s['url'] as String).endsWith('/c') &&
              s['reason'] == 'robots-disallowed'),
          isTrue,
          reason: '/c should be skipped as robots-disallowed',
        );
        expect(
          skipped.any((s) => (s['reason'] as String) == 'cross-origin'),
          isTrue,
          reason: 'the external link should be skipped as cross-origin',
        );

        // Each captured route dir has shot.png + tokens.json + skeleton.json.
        for (final r in routesList) {
          final dir = '${tmp.path}/routes/${r['dir']}';
          expect(File('$dir/shot.png').existsSync(), isTrue);
          expect(File('$dir/tokens.json').existsSync(), isTrue);
          expect(File('$dir/skeleton.json').existsSync(), isTrue);
        }

        // design_system.json merges the shared palette into one cluster/color.
        final ds = await mergeDesignSystem(tmp.path);
        expect(File('${tmp.path}/design_system.json').existsSync(), isTrue);
        final palette = (ds['palette'] as List).cast<Map<String, dynamic>>();
        final blueClusters = palette.where((p) {
          final rgb = hexToRgb(p['hex'] as String);
          final lab = rgbToLab(rgb[0], rgb[1], rgb[2]);
          final tgt = rgbToLab(0x1a, 0x73, 0xe8);
          return deltaE2000Lab(lab[0], lab[1], lab[2], tgt[0], tgt[1], tgt[2]) < 6;
        }).toList();
        expect(blueClusters.length, 1,
            reason: 'shared #1a73e8 should merge into a single cluster');
        final blueRoutes =
            (blueClusters.first['routes'] as List).cast<String>();
        expect(blueRoutes, containsAll(['/a', '/b']));
        expect(blueClusters.first['count'] as int, greaterThanOrEqualTo(2));

        // type/spacing scales are unioned across routes.
        expect(ds['type'] as List, isNotEmpty);
        expect(ds['spacing'] as List, isNotEmpty);
      } finally {
        await server.close();
        await tmp.delete(recursive: true);
      }
    });
  });

  group('robotsAllows', () {
    test('Disallow prefix blocks; 404 (no robots) allows all', () async {
      final (server, base) = await bootCrawlServer();
      final (noRobotsServer, noRobotsBase) =
          await bootCrawlServer(serveRobots: false);
      try {
        expect(await robotsAllows(base, '/a'), isTrue);
        expect(await robotsAllows(base, '/c'), isFalse);
        // No robots.txt (404) → allow everything, including /c.
        expect(await robotsAllows(noRobotsBase, '/c'), isTrue);
      } finally {
        await server.close();
        await noRobotsServer.close();
      }
    });
  });
}
