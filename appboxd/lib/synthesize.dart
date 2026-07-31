// synthesize — Dart port of tools/vendor/stages/synthesize.py (537 lines).
//
// Stage 4 of the intake pipeline: joins primitives + maps → breakdown.json +
// mock.html. No LLM — pure data processing:
//   1. attach mapping{ios,android,web} to each primitive by `id`/`id.variant`
//   2. extract design tokens from the HTML (regex on <style> + inline styles)
//   3. validate the merged object (fallback: required top fields meta/pages —
//      jsonschema is unavailable in pure-Dart land, same as the ImportError path)
//   4. render mock.html (neutral, completeness audit)
//   5. count check: primitives in mock == primitives in breakdown
//
// Deterministic: identical inputs → identical breakdown.json and mock.html.
// Pure Dart (dart:convert, dart:io, package:path only).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const _catFiles = <String, String>{
  'ios': 'ios-liquid-glass.json',
  'android': 'android-m4-expressive.json',
  'web': 'web-shadcn-ui.json',
};
const _allPlatforms = ['ios', 'android', 'web'];
const _canonFile = 'primitives-canonical.json';

// `generated` timestamp — Python default (--generated). Held constant so the
// breakdown.json output is reproducible across runs.
const _generated = '2026-06-20T00:00:00Z';

// Schema-allowed key sets: classify may emit stray annotations (sourceRef,
// note, per-primitive `skipped`) that the schema rejects because Primitive /
// Page / Component are additionalProperties:false. Sanitize to these.
final _primKeys = {
  'ref', 'id', 'variant', 'props', 'motion', 'mapping', 'sharedWith',
};
final _pageKeys = {
  'id', 'name', 'route', 'description', 'components', 'skipped',
};
final _compKeys = {
  'id', 'name', 'selector', 'role', 'primitives', 'uses', 'skipped',
};

// Design icon name → SF Symbol. A closed lookup table — a hallucinated
// sfSymbol breaks the iOS asset build, so an unmapped icon drops its tab
// (fail-loud) rather than emitting an invalid symbol.
const _iconToSfSymbol = <String, String>{
  'bolt': 'bolt.fill', 'shop': 'bag.fill', 'heart': 'heart.fill',
  'person': 'person.fill', 'bag': 'bag.fill', 'cart': 'cart.fill',
  'home': 'house.fill', 'house': 'house.fill', 'gear': 'gearshape.fill',
  'settings': 'gearshape.fill', 'search': 'magnifyingglass.fill',
  'magnifyingglass': 'magnifyingglass.fill', 'user': 'person.fill',
  'profile': 'person.fill', 'star': 'star.fill', 'bell': 'bell.fill',
  'calendar': 'calendar.fill', 'clock': 'clock.fill',
  'list': 'list.bullet.fill', 'menu': 'line.3.horizontal.fill',
  'plus': 'plus.circle.fill', 'map': 'map.fill', 'location': 'location.fill',
  'play': 'play.fill',
};

// ──────────── value helpers ────────────

// Mirror Python truthiness for the values these stages handle: None/False/0/
// ""/empty-container are falsy; everything else truthy. A non-empty string
// like "0" stays truthy, matching Python.
bool _isFalsy(dynamic x) {
  if (x == null) return true;
  if (x is bool) return !x;
  if (x is num) return x == 0;
  if (x is String) return x.isEmpty;
  if (x is List) return x.isEmpty;
  if (x is Map) return x.isEmpty;
  return false;
}

bool _isTruthy(dynamic x) => !_isFalsy(x);

// Python str() for f-string interpolation: None→"None", True→"True",
// False→"False". Used everywhere a Python f-string str()s a possibly-null value
// (id, ref, kind, symbol) so the emitted text matches byte-for-byte.
String _pyStr(dynamic x) {
  if (x == null) return 'None';
  if (x is bool) return x ? 'True' : 'False';
  return x.toString();
}

// Python str.capitalize(): first char uppercased, rest lowercased.
String _pyCapitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1).toLowerCase();
}

/// Derive a human label from a kebab/dotted id when classify omits `name`
/// (pages/components require name; id is always present).
/// 'workout-grid' → 'Workout Grid'; takes the last dot-segment, like Python.
String _labelFromId(dynamic idval) {
  if (_isFalsy(idval)) return 'Untitled';
  final seg = idval.toString().split('.').last;
  final words = seg.split(RegExp(r'[-_]+')).where((w) => w.isNotEmpty);
  return words.map(_pyCapitalize).join(' ');
}

// ──────────── token extraction ────────────

final _styleBlockRe =
    RegExp(r'<style[^>]*>(.*?)</style>', caseSensitive: false, dotAll: true);
final _inlineStyleRe =
    RegExp(r'style="([^"]*)"', caseSensitive: false);
final _colorRe = RegExp(r'--([A-Za-z0-9_-]+)\s*:\s*([^;}]+)');
final _radiiRe =
    RegExp(r'border-radius\s*:\s*([^;}]+)', caseSensitive: false);
final _fontRe = RegExp(r'font-(family|size|weight)\s*:\s*([^;}]+)');
final _shadowRe =
    RegExp(r'box-shadow\s*:\s*([^;}]+)', caseSensitive: false);
final _spacingRe = RegExp(r'(padding|margin|gap)\s*:\s*([^;}]+)');

Map<String, dynamic> _extractTokens(String html) {
  final blob = <String>[];
  for (final m in _styleBlockRe.allMatches(html)) {
    blob.add(m.group(1)!);
  }
  for (final m in _inlineStyleRe.allMatches(html)) {
    blob.add(m.group(1)!);
  }
  final css = blob.join('\n');

  // group-count-aware: a 2-group pattern builds key/value; a 1-group pattern
  // dedupes values into a self-map (radii/shadows are value-only — a key would
  // be fabricated). setdefault → FIRST occurrence wins.
  Map<String, String> grab(RegExp pat) {
    final out = <String, String>{};
    for (final m in pat.allMatches(css)) {
      if (m.groupCount >= 2) {
        out.putIfAbsent(m.group(1)!.trim(), () => m.group(2)!.trim());
      } else {
        final v = m.group(1)!.trim();
        out.putIfAbsent(v, () => v);
      }
    }
    return out;
  }

  final colors = <String, String>{};
  for (final m in _colorRe.allMatches(css)) {
    final val = m.group(2)!.trim();
    if (val.startsWith('#') || val.startsWith('rgb') || val.startsWith('hsl')) {
      colors[m.group(1)!] = val; // LAST occurrence wins (direct assign)
    }
  }
  final radii = grab(_radiiRe); // first-wins dedup
  final fonts = <String, String>{};
  for (final m in _fontRe.allMatches(css)) {
    fonts[m.group(1)!] = m.group(2)!.trim(); // last-wins
  }
  final shadows = grab(_shadowRe); // first-wins dedup
  final spacing = <String, String>{};
  for (final m in _spacingRe.allMatches(css)) {
    spacing[m.group(1)!] = m.group(2)!.trim(); // last-wins
  }
  return {
    'colors': colors,
    'radii': radii,
    'typography': fonts,
    'shadows': shadows,
    'spacing': spacing,
  };
}

// ──────────── join ────────────

/// Attach mapping{platform} to each primitive by (id,variant) + sanitize stray
/// keys. Works for any primitive container (page Component OR SharedComponent).
/// Returns (pages, shared, canonicalIds).
(List<dynamic>, List<dynamic>, Set<dynamic>) _join(
    Map<String, dynamic> primsDoc,
    Map<String, dynamic> mappings,
    List<String> platforms) {
  final canonicalIds = <dynamic>{};

  void attach(Map<String, dynamic> container) {
    final prims = (container['primitives'] as List?) ?? const [];
    for (final prim in prims) {
      final p = prim as Map<String, dynamic>;
      final pid = p['id'];
      final rawVar = p['variant'];
      // key = f"{pid}.{var}" if var else pid   (var = prim.get("variant") or "")
      final key = _isTruthy(rawVar)
          ? '${_pyStr(pid)}.${_pyStr(rawVar)}'
          : _pyStr(pid);
      final mp = mappings[key];
      if (mp == null) {
        // join miss — fabricate a flagged mapping rather than dropping
        p['mapping'] = <String, dynamic>{
          for (final plat in platforms)
            plat: <String, dynamic>{
              'stack': 'flutter',
              'bridge': 'none',
              'symbol': null,
              'nativeRef': null,
              'api': '',
              'params': <dynamic>[],
              'availability': '',
              'experimental': false,
              'notes': "NO MAPPING for id '$key'.",
              'unconfirmed': true,
            },
        };
      } else {
        p['mapping'] = mp;
      }
      canonicalIds.add(p['id']);
      p.removeWhere((k, _) => !_primKeys.contains(k));
    }
  }

  final pages = (primsDoc['pages'] as List?) ?? const [];
  for (final page in pages) {
    final pg = page as Map<String, dynamic>;
    pg.putIfAbsent('name', () => _labelFromId(pg['id']));
    final seenCids = <dynamic>{}; // backfill component id from name when omitted
    for (final comp in (pg['components'] as List?) ?? const []) {
      final c = comp as Map<String, dynamic>;
      if (_isFalsy(c['id'])) {
        final nameRaw = c['name'];
        final nameOr =
            (nameRaw is String && nameRaw.isNotEmpty) ? nameRaw : 'component';
        var base = nameOr.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
        if (base.isEmpty) base = 'component';
        var cid = base;
        var n = 2;
        while (seenCids.contains(cid)) {
          cid = '$base$n';
          n += 1;
        }
        c['id'] = cid;
      }
      seenCids.add(c['id']);
      c.putIfAbsent('name', () => _labelFromId(c['id']));
      attach(c);
      c.putIfAbsent('skipped', () => <dynamic>[]);
      c.removeWhere((k, _) => !_compKeys.contains(k));
    }
    pg.removeWhere((k, _) => !_pageKeys.contains(k));
  }

  final shared = (primsDoc['sharedComponents'] as List?) ?? const [];
  for (final sc in shared) {
    final s = sc as Map<String, dynamic>;
    s.putIfAbsent('name', () => _labelFromId(s['id']));
    // `uses` must be a positive int; LLMs sometimes emit a descriptive string
    // (e.g. "N (filtered.length)"). Coerce: leading digits, else 1.
    final u = s['uses'];
    var needsCoerce = false;
    if (u is bool) {
      needsCoerce = true;
    } else if (u is int) {
      needsCoerce = u < 1;
    } else {
      needsCoerce = true; // string / null / double / …
    }
    if (needsCoerce) {
      if (u is String) {
        final m = RegExp(r'\d+').firstMatch(u);
        s['uses'] = (m != null) ? int.parse(m.group(0)!) : 1;
      } else {
        s['uses'] = 1;
      }
    }
    attach(s);
  }

  return (pages, shared, canonicalIds);
}

// ──────────── open questions ────────────

List<String> _openQuestions(
    List<dynamic> pages, List<dynamic> shared, List<String> platforms) {
  final qs = <String>[];
  final seen = <String>{};

  void scan(String ownerPath, List<dynamic> prims) {
    for (final prim in prims) {
      final p = prim as Map<String, dynamic>;
      final mp = (p['mapping'] as Map<String, dynamic>?) ?? const {};
      for (final plat in platforms) {
        final pm = (mp[plat] as Map<String, dynamic>?) ?? const {};
        if (_isTruthy(pm['unconfirmed'])) {
          final ref = p['ref'];
          final key = '$ownerPath\x00$ref\x00$plat';
          if (seen.contains(key)) continue;
          seen.add(key);
          final sym = pm['symbol'];
          final symbol = _isTruthy(sym) ? sym : pm['nativeRef'];
          qs.add("${_pyStr(ref)} @ $ownerPath: "
              "confirm $plat symbol '${_pyStr(symbol)}'");
        }
      }
    }
  }

  for (final page in pages) {
    final pg = page as Map<String, dynamic>;
    final pageId = _pyStr(pg['id']);
    for (final comp in (pg['components'] as List?) ?? const []) {
      final c = comp as Map<String, dynamic>;
      scan('$pageId/${_pyStr(c['id'])}',
          (c['primitives'] as List?) ?? const []);
    }
  }
  for (final sc in shared) {
    final s = sc as Map<String, dynamic>;
    scan('shared/${_pyStr(s['id'])}', (s['primitives'] as List?) ?? const []);
  }
  return qs;
}

// ──────────── mock render ────────────

String _mockElement(Map<String, dynamic> prim) {
  // One neutral chip per primitive — the mock is a completeness audit (count +
  // "nothing dropped"), not a styled preview.
  final variant = prim['variant'];
  final suffix = _isTruthy(variant) ? '.${_pyStr(variant)}' : '';
  return '<div class="mc-box">${_pyStr(prim['id'])}$suffix</div>';
}

(String, int) _renderMock(List<dynamic> pages, List<dynamic> shared) {
  final parts = <String>[
    "<!doctype html><html><head><meta charset='utf-8'>",
    "<title>flutter_crew mock</title>",
    "<style>body{font:14px/1.4 system-ui;margin:24px}",
    ".page{margin-bottom:32px;border-top:2px solid #888;padding-top:8px}",
    ".comp{margin:12px 0;padding:8px;border:1px dashed #aaa;border-radius:6px}",
    ".prim{display:inline-block;margin:4px;padding:6px;background:#f4f4f5;"
        "border-radius:4px}",
    ".mc-box{padding:6px;background:#eee}",
    "</style></head><body>",
  ];
  var count = 0;
  for (final page in pages) {
    final pg = page as Map<String, dynamic>;
    parts.add('<section class="page"><h2>${_pyStr(pg['name'])}</h2>');
    for (final comp in (pg['components'] as List?) ?? const []) {
      final c = comp as Map<String, dynamic>;
      parts.add('<div class="comp"><h3>${_pyStr(c['name'])}</h3>');
      for (final prim in (c['primitives'] as List?) ?? const []) {
        parts.add(
            '<div class="prim">${_mockElement(prim as Map<String, dynamic>)}</div>');
        count++;
      }
      parts.add('</div>');
    }
    parts.add('</section>');
  }
  if (shared.isNotEmpty) {
    parts.add('<section class="page"><h2>Shared components</h2>');
    for (final sc in shared) {
      final s = sc as Map<String, dynamic>;
      parts.add(
          '<div class="comp"><h3>${_pyStr(s['name'])} (${_pyStr(s['kind'])})</h3>');
      for (final prim in (s['primitives'] as List?) ?? const []) {
        parts.add(
            '<div class="prim">${_mockElement(prim as Map<String, dynamic>)}</div>');
        count++;
      }
      parts.add('</div>');
    }
    parts.add('</section>');
  }
  parts.add('</body></html>');
  return (parts.join('\n'), count);
}

// ──────────── primary nav (bottom tab bar) ────────────

/// Lift the classify `primaryNav` hint into the canonical breakdown manifest.
/// Applies the deterministic translation: icon → sfSymbol (closed table,
/// fail-loud on unmapped), badgeField detection (shop/cart tab → 'cartCount'),
/// and dangling-route drop. Returns null when no bottom nav survives so the
/// breakdown omits primaryNav entirely (golden-stable for no-tab designs).
Map<String, dynamic>? _resolvePrimaryNav(
    Map<String, dynamic> primsDoc, List<dynamic> screenFlow) {
  final hint = primsDoc['primaryNav'];
  if (_isFalsy(hint) || hint is! Map) return null;
  final rawTabs = hint['tabs'];
  if (rawTabs is! List || rawTabs.length < 2) return null; // <2 tabs ≠ a shell

  final flowIds = <dynamic>{};
  for (final s in screenFlow) {
    final sid = (s as Map<String, dynamic>)['id'];
    if (_isTruthy(sid)) flowIds.add(sid);
  }

  final tabs = <Map<String, dynamic>>[];
  for (final t in rawTabs) {
    if (t is! Map) continue;
    final screen = t['screen'];
    final tabId = _isTruthy(screen) ? screen : t['id']; // `or`
    final label = t['label'];
    final iconRaw = t['icon'];
    final icon =
        (_isTruthy(iconRaw) ? iconRaw.toString() : '').trim().toLowerCase();
    if (!_isTruthy(tabId) || !_isTruthy(label) || icon.isEmpty) continue;
    if (flowIds.isNotEmpty && !flowIds.contains(tabId)) {
      continue; // tab targets a screen the LLM did not reconcile → no dangling route
    }
    final sf = _iconToSfSymbol[icon];
    if (sf == null) {
      stderr.writeln("primaryNav: unmapped design icon '$icon' — tab '$tabId' "
          'dropped (extend _ICON_TO_SFSYMBOL to render it)');
      continue;
    }
    final tab = <String, dynamic>{'id': tabId, 'label': label, 'sfSymbol': sf};
    // cart badge lives on the shopping tab — detected by id/icon, not label.
    if (tabId == 'shop' ||
        tabId == 'cart' ||
        icon == 'shop' ||
        icon == 'bag' ||
        icon == 'cart') {
      tab['badgeField'] = 'cartCount';
    }
    tabs.add(tab);
  }
  if (tabs.length < 2) return null; // too few tabs survived → no nav shell
  return <String, dynamic>{'kind': 'surface.tabbar', 'tabs': tabs};
}

// ──────────── validation ────────────

(bool, String) _validate(Map<String, dynamic> breakdown) {
  // jsonschema is unavailable in pure-Dart land — always the fallback path the
  // Python takes on ImportError: require the top fields downstream depends on.
  for (final req in ['meta', 'pages']) {
    if (!breakdown.containsKey(req)) {
      return (false, 'missing top field $req');
    }
  }
  return (true, 'fallback required-check OK (jsonschema not installed)');
}

// ──────────── sorted, indented JSON (matches Python json.dumps sort_keys +
// indent=2 + ensure_ascii=False) ────────────

String _dumpSorted(dynamic obj, [String indent = '']) {
  if (obj is Map) {
    if (obj.isEmpty) return '{}';
    final keys = obj.keys.map((e) => e.toString()).toList()..sort();
    final child = '$indent  ';
    final parts = <String>[];
    for (final k in keys) {
      parts.add('$child${jsonEncode(k)}: ${_dumpSorted(obj[k], child)}');
    }
    return '{\n${parts.join(',\n')}\n$indent}';
  } else if (obj is List) {
    if (obj.isEmpty) return '[]';
    final child = '$indent  ';
    final parts = obj.map((e) => '$child${_dumpSorted(e, child)}');
    return '[\n${parts.join(',\n')}\n$indent]';
  } else {
    return jsonEncode(obj);
  }
}

// ──────────── entry point ────────────

/// Stage 4: join primitives + maps → breakdown.json + mock.html.
///
/// Returns 0 on success, 1 on any failure (read error, non-canonical id,
/// schema/required-field failure, primitive-count mismatch, write error).
int synthesize(String primitivesPath, String mapsPath, String designHtmlPath,
    String catalogDir, String outDir) {
  try {
    return _synthesize(primitivesPath, mapsPath, designHtmlPath, catalogDir, outDir);
  } catch (e) {
    stderr.writeln('synthesize: $e');
    return 1;
  }
}

int _synthesize(String primitivesPath, String mapsPath, String designHtmlPath,
    String catalogDir, String outDir) {
  Map<String, dynamic> primsDoc;
  Map<String, dynamic> mapsDoc;
  String html;
  Map<String, Map<String, dynamic>> catalogs;
  Map<String, dynamic> canon;

  try {
    final pd = jsonDecode(File(primitivesPath).readAsStringSync());
    if (pd is! Map<String, dynamic>) {
      stderr.writeln('synthesize: $primitivesPath is not a JSON object');
      return 1;
    }
    primsDoc = pd;
    final md = jsonDecode(File(mapsPath).readAsStringSync());
    if (md is! Map<String, dynamic>) {
      stderr.writeln('synthesize: $mapsPath is not a JSON object');
      return 1;
    }
    mapsDoc = md;
    html = File(designHtmlPath).readAsStringSync();
    catalogs = {};
    for (final entry in _catFiles.entries) {
      catalogs[entry.key] = jsonDecode(
              File(p.join(catalogDir, entry.value)).readAsStringSync())
          as Map<String, dynamic>;
    }
    canon = jsonDecode(File(p.join(catalogDir, _canonFile)).readAsStringSync())
        as Map<String, dynamic>;
  } catch (e) {
    stderr.writeln('synthesize: failed to read inputs — $e');
    return 1;
  }

  // no --platforms/--config in this port's signature → default all three
  final platforms = List<String>.from(_allPlatforms);
  final mappings =
      (mapsDoc['mappings'] as Map<String, dynamic>?) ?? <String, dynamic>{};

  final (pages, shared, canonicalIds) = _join(primsDoc, mappings, platforms);

  // screenFlow: guard.value must be a string; a null value = unconditional →
  // drop guard; otherwise stringify (bool → lowercased, like str(v).lower()).
  final screenFlow = (primsDoc['screenFlow'] as List?) ?? <dynamic>[];
  for (final s in screenFlow) {
    final g = (s as Map<String, dynamic>)['guard'];
    if (g is Map) {
      final v = g['value'];
      if (v == null) {
        s.remove('guard');
      } else if (v is! String) {
        g['value'] = (v is bool) ? (v ? 'true' : 'false') : v.toString();
      }
    }
  }

  // every primitive id must be canonical
  final canonIds = <dynamic>{
    for (final c in (canon['primitives'] as List))
      (c as Map<String, dynamic>)['id'],
  };
  final hallucinated = canonicalIds.difference(canonIds).toList()..sort();
  if (hallucinated.isNotEmpty) {
    stderr.writeln('ERROR: non-canonical ids: $hallucinated');
    return 1;
  }

  final tokens = _extractTokens(html);
  final openQs = _openQuestions(pages, shared, platforms);
  final primaryNav = _resolvePrimaryNav(primsDoc, screenFlow);
  // exclusions only arrive via --exclusions (not in this port's signature)
  final exclusions = <dynamic>[];

  final breakdown = <String, dynamic>{
    'meta': <String, dynamic>{
      'source': designHtmlPath,
      'crewVersion': 'flutter_crew-deterministic',
      'platforms': platforms,
      'generated': _generated,
      'canonicalVersion': canon['version'] ?? '',
      'catalogVersions': <String, dynamic>{
        for (final p in platforms) p: catalogs[p]!['version'] ?? '',
      },
    },
    'tokens': tokens,
    'pages': pages,
    'openQuestions': openQs,
    'exclusions': exclusions,
    'screenFlow': screenFlow,
    'sharedComponents': shared,
    'skipped': (primsDoc['skipped'] as List?) ?? <dynamic>[],
  };
  // primaryNav emitted ONLY when the design declares a bottom tab bar —
  // omit when null so no-tab designs stay byte-identical (golden-neutral).
  if (primaryNav != null) {
    breakdown['primaryNav'] = primaryNav;
  }

  final (ok, msg) = _validate(breakdown);
  if (!ok) {
    stderr.writeln('SCHEMA INVALID: $msg');
    return 1;
  }
  stdout.writeln('schema: $msg');

  try {
    Directory(outDir).createSync(recursive: true);
    File(p.join(outDir, 'breakdown.json'))
        .writeAsStringSync(_dumpSorted(breakdown));
    final (mock, mockCount) = _renderMock(pages, shared);
    File(p.join(outDir, 'mock.html')).writeAsStringSync(mock);

    var primTotal = 0;
    for (final pg in pages) {
      for (final c in ((pg as Map<String, dynamic>)['components'] as List?) ??
          const []) {
        primTotal += (((c as Map<String, dynamic>)['primitives'] as List?) ??
                const [])
            .length;
      }
    }
    for (final sc in shared) {
      primTotal +=
          ((sc as Map<String, dynamic>)['primitives'] as List? ?? const []).length;
    }
    if (mockCount != primTotal) {
      stderr.writeln(
          'ERROR: mock=$mockCount breakdown=$primTotal (dropped primitive)');
      return 1;
    }
    stdout.writeln('wrote breakdown.json/mock.html → $outDir '
        '(platforms=$platforms pages=${pages.length} prims=$primTotal '
        'openQs=${openQs.length} excluded=${exclusions.length})');
    return 0;
  } catch (e) {
    stderr.writeln('synthesize: failed to write output — $e');
    return 1;
  }
}
