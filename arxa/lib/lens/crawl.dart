// Multi-route lens crawl + cross-route design-token merge.
//
// Ports probe-runner's web_crawl (per-route screenshot+tokens+skeleton, one-hop
// same-origin expansion with robots.txt fail-closed) and site_merge (ΔE2000
// palette clustering → design_system.json). The moodboard-at-scale capability:
// the arxa-moodboarder skill fans this out by hand today.
library;

import 'dart:convert';
import 'dart:io';

import 'package:arxa/lens.dart';
import 'daemon.dart';

/// Outcome of a crawl: captured route paths, the output dir, and skipped URLs.
class CrawlResult {
  CrawlResult({
    required this.routes,
    required this.outDir,
    required this.skipped,
  });
  final List<String> routes;
  final String outDir;
  final List<String> skipped;
}

/// Crawl [baseUrl], capturing screenshot + tokens + skeleton per route.
///
/// Seeds with [routes]; when [crawl] is true, expands one hop by harvesting
/// same-origin `a[href]` links from each captured page. robots.txt is fetched
/// once and applied fail-closed (404 → allow, non-200 / unparsable → disallow).
/// Captures are capped at [crawlMax] with a [delayMs] politeness gap between
/// route captures. Console/page errors auto-fail a route (lens doctrine): the
/// route is recorded in `skipped`, not in `routes`.
///
// kimitail: one Chrome per artifact per route — captureGolden / extractTokens /
// captureSkeleton each manage their own single Chrome, run sequentially. Reuses
// the Task-3/5 modules verbatim (no orchestration duplication); share one
// session across the three artifacts if crawl latency ever becomes a concern.
Future<CrawlResult> crawlSite(
  String baseUrl, {
  List<String> routes = const ['/'],
  bool crawl = false,
  int crawlMax = 20,
  String? outDir,
  int width = 390,
  int height = 844,
  int settleMs = 1500,
  int delayMs = 2000,
}) async {
  outDir ??= _defaultOutDir(baseUrl);
  final baseUri = Uri.parse(baseUrl);

  final queue = <String>[]; // paths left to visit
  final seen = <String>{}; // fingerprints ever queued (dedup)
  final discovered = <String, bool>{}; // path -> crawl-discovered?
  for (final r in routes) {
    if (seen.add(_fingerprint(r))) {
      queue.add(r);
      discovered[r] = false;
    }
  }

  final robots = await _fetchRobots(baseUrl);
  final routeRecords = <Map<String, dynamic>>[];
  final skipped = <Map<String, dynamic>>[]; // {url, reason}
  var dirIdx = 0;

  while (queue.isNotEmpty && routeRecords.length < crawlMax) {
    final path = queue.removeAt(0);

    if (!_robotsAllows(robots, path)) {
      skipped.add({'url': '$baseUrl$path', 'reason': 'robots-disallowed'});
      continue;
    }

    if (dirIdx > 0 && delayMs > 0) {
      await Future.delayed(Duration(milliseconds: delayMs));
    }

    final url = '$baseUrl$path';
    // One Chrome each (see kimitail above); errors fail the route before write.
    final tokens = await extractTokens(url, width, height, settleMs: settleMs);
    if (tokens['certified'] != true) {
      skipped.add({'url': url, 'reason': 'console/page errors'});
      continue;
    }
    final skeleton =
        await captureSkeleton(url, width: width, height: height, settleMs: settleMs);
    if (skeleton['certified'] != true) {
      skipped.add({'url': url, 'reason': 'console/page errors'});
      continue;
    }
    final png = await captureGolden(url, width, height, settleMs: settleMs);

    final dirName = 'r${dirIdx.toString().padLeft(2, '0')}';
    final routeDir = '$outDir/routes/$dirName';
    final pngFile = File('$routeDir/shot.png');
    pngFile.parent.createSync(recursive: true);
    pngFile.writeAsBytesSync(png);
    writeLensJson('$routeDir/tokens.json', _encode(tokens));
    writeLensJson('$routeDir/skeleton.json', _encode(skeleton));

    routeRecords.add({
      'route': path,
      'dir': dirName,
      'discovered': discovered[path] ?? true,
    });
    dirIdx++;

    if (crawl) {
      final links = await _harvestLinks(url, width, height, settleMs);
      for (final link in links) {
        final l = Uri.tryParse(link);
        if (l == null) continue;
        if (!l.isScheme('http') && !l.isScheme('https')) continue;
        if (!_sameOrigin(baseUri, l)) {
          skipped.add({'url': link, 'reason': 'cross-origin'});
          continue;
        }
        final linkPath = l.path.isEmpty ? '/' : l.path;
        if (seen.add(linkPath)) {
          discovered[linkPath] = true;
          queue.add(linkPath);
        }
      }
    }
  }

  final site = {
    'base': baseUrl,
    'routes': routeRecords,
    'skipped': skipped,
  };
  writeLensJson('$outDir/site.json', _encode(site));

  return CrawlResult(
    routes: [for (final r in routeRecords) r['route'] as String],
    outDir: outDir,
    skipped: [for (final s in skipped) s['url'] as String],
  );
}

/// Merge every `routes/*/tokens.json` under [siteDir] into a combined
/// `design_system.json`: palette clustered by ΔE2000 < 6 (single-linkage),
/// type/spacing scales unioned by value. Returns the merged document.
Future<Map<String, dynamic>> mergeDesignSystem(String siteDir) async {
  final routesDir = Directory('$siteDir/routes');
  final paletteItems = <Map<String, dynamic>>[]; // {hex, count, route}
  final typeScale = <int, int>{}; // value -> total count
  final spacingScale = <int, int>{};

  if (routesDir.existsSync()) {
    for (final entry in routesDir.listSync()) {
      if (entry is! Directory) continue;
      final tf = File('${entry.path}/tokens.json');
      if (!tf.existsSync()) continue;
      final tokens = jsonDecode(tf.readAsStringSync()) as Map<String, dynamic>;
      final route = Uri.parse(tokens['url'] as String).path;
      for (final p in (tokens['palette'] as List).cast<Map>()) {
        paletteItems.add({'hex': p['hex'], 'count': p['count'], 'route': route});
      }
      for (final t in (tokens['type'] as List).cast<Map>()) {
        final v = (t['value'] as num).toInt();
        typeScale[v] = (typeScale[v] ?? 0) + (t['count'] as int);
      }
      for (final s in (tokens['spacing'] as List).cast<Map>()) {
        final v = (s['value'] as num).toInt();
        spacingScale[v] = (spacingScale[v] ?? 0) + (s['count'] as int);
      }
    }
  }

  final result = {
    'palette': _clusterPalette(paletteItems, 6.0),
    'type': _unionScale(typeScale),
    'spacing': _unionScale(spacingScale),
  };
  writeLensJson('$siteDir/design_system.json', _encode(result));
  return result;
}

/// Fetch [baseUrl]'s /robots.txt and check [path] against its `User-agent: *`
/// group. 404 → allow; non-200 or unparsable body → disallow (fail-closed).
Future<bool> robotsAllows(String baseUrl, String path) async {
  final robots = await _fetchRobots(baseUrl);
  return _robotsAllows(robots, path);
}

// ── robots ──────────────────────────────────────────────────────────

class _Robots {
  _Robots({this.disallowAll = false, List<String>? disallow})
      : disallow = disallow ?? const [];
  final bool disallowAll; // fetch failure / unparsable → disallow everything
  final List<String> disallow; // `User-agent: *` Disallow: path prefixes
}

Future<_Robots> _fetchRobots(String baseUrl) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse('$baseUrl/robots.txt'));
    final res = await req.close();
    if (res.statusCode == 404) return _Robots(); // no robots → allow all
    if (res.statusCode != 200) return _Robots(disallowAll: true); // fail-closed
    final body = await res.transform(utf8.decoder).join();
    final parsed = _parseRobots(body);
    if (parsed == null) return _Robots(disallowAll: true); // unparsable → fail-closed
    return _Robots(disallow: parsed);
  } catch (_) {
    return _Robots(disallowAll: true); // network error → fail-closed
  } finally {
    client.close();
  }
}

/// Parse the `User-agent: *` group's `Disallow:` prefixes. Returns null when a
/// non-comment line has no colon (structural garbage → fail-closed). Unknown
/// directives (Allow/Crawl-delay/Sitemap/…) are ignored.
// kimitail: Allow/rules-precedence unsupported — arxa surfaces never use them;
// swap for a full parser (e.g. fielded group state) if a real target needs it.
List<String>? _parseRobots(String body) {
  final disallow = <String>[];
  var inStar = false;
  for (final raw in body.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final colon = line.indexOf(':');
    if (colon < 0) return null;
    final field = line.substring(0, colon).trim().toLowerCase();
    final value = line.substring(colon + 1).trim();
    if (field == 'user-agent') {
      inStar = value == '*';
    } else if (field == 'disallow') {
      if (inStar) disallow.add(value);
    }
  }
  return disallow;
}

bool _robotsAllows(_Robots robots, String path) {
  if (robots.disallowAll) return false;
  for (final prefix in robots.disallow) {
    if (prefix.isEmpty) continue; // `Disallow:` with no value = allow all
    if (path.startsWith(prefix)) return false;
  }
  return true;
}

// ── link harvest ────────────────────────────────────────────────────

const String _harvestJs = r'''
(() => {
  const out = [];
  for (const a of document.querySelectorAll('a[href]')) out.push(a.href);
  return out;
})()
''';

Future<List<String>> _harvestLinks(
  String url,
  int width,
  int height,
  int settleMs,
) async {
  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: settleMs);
    final raw = await tab.evaluate(_harvestJs) as List;
    return raw.cast<String>();
  } finally {
    await client.close();
  }
}

// ── palette ΔE2000 clustering ───────────────────────────────────────

/// Single-linkage cluster palette items whose ΔE2000 < [threshold]. Each
/// cluster → {hex (most frequent member), routes (unique, sorted), count (sum)},
/// sorted by count desc.
List<Map<String, dynamic>> _clusterPalette(
  List<Map<String, dynamic>> items,
  double threshold,
) {
  final clusters = <List<Map<String, dynamic>>>[];
  for (final item in items) {
    final lab = _hexToLab(item['hex'] as String);
    final near = <int>[];
    for (var i = 0; i < clusters.length; i++) {
      for (final m in clusters[i]) {
        final mlab = _hexToLab(m['hex'] as String);
        if (deltaE2000Lab(
                lab[0], lab[1], lab[2], mlab[0], mlab[1], mlab[2]) <
            threshold) {
          near.add(i);
          break;
        }
      }
    }
    if (near.isEmpty) {
      clusters.add([item]);
    } else {
      clusters[near.first].add(item);
      // Merge any other near clusters into the first (single-linkage).
      for (var j = near.length - 1; j >= 1; j--) {
        clusters[near.first].addAll(clusters[near[j]]);
        clusters.removeAt(near[j]);
      }
    }
  }

  final out = <Map<String, dynamic>>[];
  for (final c in clusters) {
    c.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    final routes = <String>{for (final m in c) m['route'] as String}.toList()
      ..sort();
    final count = c.fold<int>(0, (acc, m) => acc + (m['count'] as int));
    out.add({'hex': c.first['hex'], 'routes': routes, 'count': count});
  }
  out.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
  return out;
}

// ── helpers ─────────────────────────────────────────────────────────

List<Map<String, dynamic>> _unionScale(Map<int, int> scale) {
  final keys = scale.keys.toList()..sort();
  return [for (final k in keys) {'value': k, 'count': scale[k]}];
}

List<int> _hexToRgb(String hex) {
  final h = hex.replaceFirst('#', '');
  return [
    int.parse(h.substring(0, 2), radix: 16),
    int.parse(h.substring(2, 4), radix: 16),
    int.parse(h.substring(4, 6), radix: 16),
  ];
}

List<double> _hexToLab(String hex) {
  final rgb = _hexToRgb(hex);
  return rgbToLab(rgb[0], rgb[1], rgb[2]);
}

/// URL fingerprint: path only (query/hash dropped).
String _fingerprint(String pathOrUrl) {
  final u = Uri.tryParse(pathOrUrl);
  return (u != null && u.path.isNotEmpty) ? u.path : pathOrUrl;
}

bool _sameOrigin(Uri a, Uri b) {
  int port(Uri u) {
    if (u.port != 0) return u.port;
    return u.isScheme('https') ? 443 : 80;
  }

  return a.host == b.host && port(a) == port(b);
}

String _encode(Map<String, dynamic> m) =>
    const JsonEncoder.withIndent('  ').convert(m);

String _defaultOutDir(String baseUrl) {
  final host = Uri.tryParse(baseUrl)?.host ?? 'tmp';
  final safe = host.replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '_');
  final ts = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '');
  return 'designs/${safe.isEmpty ? 'tmp' : safe}/evidence/crawl-$ts';
}
