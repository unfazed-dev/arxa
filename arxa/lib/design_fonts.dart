/// The Arxa Dial's font plane (grilled 2026-09-13, seven decisions):
/// typography as a published, live-switchable axis — the palette plane's
/// law (design_palettes.dart, ADDENDUM 17) one seat over.
///
///   fonts.json (artifact root)  declares the plane: per-artifact ROLES
///     (grilled Q6 — arxa-site: display+body; suczka: display+body+
///     editorial; the starter: one body role on the system stack), each
///     owning CHOICES (up to five seeded, catalog picks appended — the
///     palette's seeded-five law). A choice = one Google Fonts family +
///     its css2 query segment + the fallback stack. css2 null = a system
///     stack choice (the starter ships CDN-free at birth).
///   html[data-font-`<role>`=`<choice>`]  is the apply seam, one attribute
///     per role (grilled Q1: INDEPENDENT per-role dropdowns — each role
///     publishes alone; the axes cell is an object role -> choice id).
///   assets/styles/fonts/font-`<role>`-`<id>`.css  generated token-override
///     sheets (the DEFAULT choice per role is the base corpus, no sheet —
///     the palette's default-is-base law).
///   assets/app/font.js  the artifact-owned applier (palette.js's shape):
///     owns the attributes, the ONE Google Fonts css2 <link>, localStorage
///     memory, ?font=`<role>:<id>` receipts, the arxa:font broadcast, and
///     (deployed static mode) the remote settle + the public font ear.
///
/// Families load from the Google Fonts CDN BY NAME — the designer's
/// no-binaries law (type.css: ".woff2 files would redistribute licensed
/// fonts"). css2 is CORS-open (access-control-allow-origin: *, measured
/// 2026-09-13) so the dial previews live specimens the same way.
///
/// The catalog (the dropdown's list, grilled Q3): fonts.google.com/
/// metadata/fonts is same-site-only (cross-origin-resource-policy, no
/// ACAO — the browser canNOT fetch it), so THIS module fetches it
/// server-side, trims it to the searchable fields, caches it under
/// ~/.arxa/font-catalog.json, and the dial island searches through the
/// design server's /__dial/font-catalog route.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'design_axes.dart' show axisValuePattern;
import 'project.dart' show arxaHome;

// ── the manifest ─────────────────────────────────────────────────────────

/// One switchable family within one role.
class FontChoice {
  const FontChoice({
    required this.id,
    required this.family,
    required this.stack,
    this.category,
    this.css2,
    this.seeded = false,
    this.source,
    this.sheet,
  });

  final String id; // slug, the html[data-font-<role>] value
  final String family; // the Google Fonts family (or a system stack name)
  final String stack; // the full font-family value, quoted family first
  final String? category; // Serif / Sans Serif / Display / Monospace
  final String? css2; // the css2 query segment; null = system stack
  final bool seeded;
  final String? source;
  final String? sheet; // generated override sheet href (null for defaults)

  Map<String, Object?> toJson() => {
        'id': id,
        'family': family,
        'stack': stack,
        if (category != null) 'category': category,
        if (css2 != null) 'css2': css2,
        if (seeded) 'seeded': true,
        if (source != null) 'source': source,
        if (sheet != null) 'sheet': sheet,
      };

  static FontChoice? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], family = json['family'], stack = json['stack'];
    if (id is! String || !axisValuePattern.hasMatch(id)) return null;
    if (family is! String || family.isEmpty) return null;
    if (stack is! String || stack.isEmpty) return null;
    final css2 = json['css2'];
    if (css2 != null &&
        (css2 is! String ||
            (!css2.startsWith('family=') && css2.isNotEmpty))) {
      return null;
    }
    return FontChoice(
      id: id,
      family: family,
      stack: stack,
      category: json['category'] as String?,
      css2: css2 is String && css2.isNotEmpty ? css2 : null,
      seeded: json['seeded'] == true,
      source: json['source'] as String?,
      sheet: json['sheet'] as String?,
    );
  }
}

/// One typographic role and its choices (grilled Q6: per-artifact roles).
class FontRole {
  const FontRole({
    required this.id,
    required this.name,
    required this.token,
    required this.choices,
  });

  final String id; // slug, the html[data-font-<id>] suffix
  final String name; // human label in the tray
  final String token; // the css custom property the sheets override
  final List<FontChoice> choices;

  bool declares(String choiceId) => choices.any((c) => c.id == choiceId);

  FontChoice? choice(String choiceId) {
    for (final c in choices) {
      if (c.id == choiceId) return c;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'token': token,
        'choices': [for (final c in choices) c.toJson()],
      };

  static FontRole? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], name = json['name'], token = json['token'];
    final list = json['choices'];
    if (id is! String || !axisValuePattern.hasMatch(id)) return null;
    if (name is! String || name.isEmpty) return null;
    if (token is! String || !token.startsWith('--')) return null;
    if (list is! List || list.isEmpty) return null;
    final choices = <FontChoice>[];
    for (final raw in list) {
      final c = FontChoice.fromJson(raw);
      if (c == null) return null;
      choices.add(c);
    }
    return FontRole(id: id, name: name, token: token, choices: choices);
  }
}

class FontPlaneManifest {
  FontPlaneManifest({required this.defaultPicks, required this.roles});

  /// role id -> choice id (the shipped defaults = the base corpus).
  final Map<String, String> defaultPicks;
  final List<FontRole> roles;

  FontRole? role(String id) {
    for (final r in roles) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Lawful picks: every key a declared role, every value a declared
  /// choice of that role. Empty map = no font picks stored.
  bool declaresAll(Map<String, String> picks) {
    for (final e in picks.entries) {
      final r = role(e.key);
      if (r == null || !r.declares(e.value)) return false;
    }
    return true;
  }

  static FontPlaneManifest? load(String artifactDir) {
    try {
      final f = File(p.join(artifactDir, 'fonts.json'));
      if (!f.existsSync()) return null;
      final parsed = jsonDecode(f.readAsStringSync());
      if (parsed is! Map) return null;
      final def = parsed['default'];
      final list = parsed['roles'];
      if (def is! Map || list is! List) return null;
      final defaults = <String, String>{};
      for (final e in def.entries) {
        if (e.key is String && e.value is String) {
          defaults[e.key as String] = e.value as String;
        }
      }
      final roles = <FontRole>[];
      for (final raw in list) {
        final r = FontRole.fromJson(raw);
        if (r == null) return null;
        roles.add(r);
      }
      if (roles.isEmpty) return null;
      final m = FontPlaneManifest(defaultPicks: defaults, roles: roles);
      final roleIds = roles.map((r) => r.id).toSet();
      if (defaults.length != roleIds.length || !m.declaresAll(defaults)) {
        return null;
      }
      return m;
    } catch (_) {
      return null;
    }
  }

  void save(String artifactDir) {
    final f = File(p.join(artifactDir, 'fonts.json'));
    const encoder = JsonEncoder.withIndent('  ');
    f.writeAsStringSync(encoder.convert({
      'version': 1,
      'comment': 'Font plane declaration (grilled 2026-09-13). roles = this '
          "artifact's font roles; each role owns choices (the seeded five + "
          'catalog picks appended, the palette law). id = the '
          'html[data-font-<role>] value; family = the Google Fonts family; '
          'css2 = its css2 query segment (null = a system stack); stack = '
          'the fallback value. The DEFAULT choice per role is the base '
          'corpus (no sheet); every other choice ships a generated token '
          'override under /assets/styles/fonts/. Catalog picks append here '
          'with a generated sheet, persist, and ship on the next eject.',
      'default': defaultPicks,
      'roles': [for (final r in roles) r.toJson()],
    }));
  }
}

// ── the serve-time application ───────────────────────────────────────────

final _htmlTagPattern = RegExp(r'<html\b[^>]*>');

class ServedFont {
  const ServedFont({
    required this.html,
    required this.active,
    required this.published,
    required this.fontsConfig,
  });

  final String html;
  final Map<String, String> active;
  final Map<String, String> published;
  final Map<String, Object?> fontsConfig;
}

/// Resolve and apply the font picks for one served page. Precedence per
/// ROLE (the independence law): a VALID ?font=`<role>:<id>` receipt beats
/// the stored pick beats the shipped default; unknown values fall through
/// silently — a probe pointing at a deleted choice gets the default.
ServedFont applyFontToServedHtml(
  String html, {
  required Map<String, String> query,
  required Map<String, String>? stored,
  required FontPlaneManifest manifest,
}) {
  final override = <String, String>{};
  final raw = query['font'];
  if (raw != null) {
    for (final part in raw.split(',')) {
      final seg = part.split(':');
      if (seg.length == 2) override[seg[0].trim()] = seg[1].trim();
    }
  }

  String resolveRole(
      FontRole role, String? overrideValue, String? storedValue) {
    if (overrideValue != null && role.declares(overrideValue)) {
      return overrideValue;
    }
    if (storedValue != null && role.declares(storedValue)) {
      return storedValue;
    }
    return manifest.defaultPicks[role.id] ?? role.choices.first.id;
  }

  final published = <String, String>{};
  final active = <String, String>{};
  for (final role in manifest.roles) {
    published[role.id] = resolveRole(role, null, stored?[role.id]);
    active[role.id] = resolveRole(role, override[role.id], stored?[role.id]);
  }

  var out = html;
  final htmlMatch = _htmlTagPattern.firstMatch(out);
  if (htmlMatch != null) {
    final tag = htmlMatch.group(0)!;
    // Strip every stale data-font-* attribute, then stamp the active one
    // per role (attribute-order robust, same as the palette seam).
    var core =
        tag.replaceAll(RegExp(r'\s+data-font-[a-z0-9-]+="[^"]*"'), '');
    final selfClosed = core.endsWith('/>');
    core = core.substring(0, core.length - (selfClosed ? 2 : 1));
    final stamps = StringBuffer();
    for (final role in manifest.roles) {
      stamps.write(
          ' data-font-${role.id}="${active[role.id] ?? ''}"');
    }
    final next = core + stamps.toString() + (selfClosed ? '/>' : '>');
    if (next != tag) out = out.replaceFirst(tag, next);
  }

  // Wire every declared override sheet (the ADDENDUM 18 law, verbatim):
  // the artifact's frame statically links nothing font-wise — sheets are
  // injected serve-time so ingested choices dress without a frame edit.
  // Dedup by href keeps any static link single.
  final links = StringBuffer();
  for (final role in manifest.roles) {
    for (final c in role.choices) {
      final sheet = c.sheet;
      if (sheet == null || sheet.isEmpty) continue;
      if (out.contains('href="$sheet"')) continue;
      links.write('<link rel="stylesheet" href="$sheet" data-font-sheet="${role.id}-${c.id}">');
    }
  }
  if (links.isNotEmpty) out = out.replaceFirst('</head>', '$links</head>');

  return ServedFont(
    html: out,
    active: active,
    published: published,
    fontsConfig: {
      'default': manifest.defaultPicks,
      'roles': [for (final r in manifest.roles) r.toJson()],
    },
  );
}

// ── ingestion (a catalog pick becomes a choice) ─────────────────────────

/// The searchable catalog entry, trimmed from Google's metadata feed.
class FontCatalogEntry {
  const FontCatalogEntry({
    required this.family,
    required this.category,
    required this.weights,
    this.variableWght,
    this.italic = false,
    this.popularity = 0,
  });

  final String family;
  final String category;
  final List<int> weights;
  final List<int>? variableWght; // [min, max] when the family is variable
  final bool italic;
  final int popularity;

  Map<String, Object?> toJson() => {
        'family': family,
        'category': category,
        'weights': weights,
        if (variableWght != null) 'variableWght': variableWght,
        'italic': italic,
        'popularity': popularity,
      };

  static FontCatalogEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final family = json['family'], category = json['category'];
    if (family is! String || family.isEmpty) return null;
    if (category is! String || category.isEmpty) return null;
    final weights = json['weights'];
    if (weights is! List) return null;
    return FontCatalogEntry(
      family: family,
      category: category,
      weights: [for (final w in weights) (w is num) ? w.round() : 400],
      variableWght: json['variableWght'] is List
          ? [
              for (final w in json['variableWght'] as List)
                (w is num) ? w.round() : 400
            ]
          : null,
      italic: json['italic'] == true,
      popularity:
          json['popularity'] is num ? (json['popularity'] as num).round() : 0,
    );
  }
}

/// family name -> url-lawful choice id ("Space Grotesk" -> space-grotesk).
String fontChoiceId(String family) => family
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

/// The css2 query segment for a catalog entry. Browsers download only the
/// faces they actually render, so a generous segment (full variable range
/// + italics when present) costs nothing until used.
String css2SegmentFor(FontCatalogEntry e) {
  final fam = e.family.replaceAll(' ', '+');
  final v = e.variableWght;
  String wght() {
    if (v != null && v.length == 2) return '${v[0]}..${v[1]}';
    final ws = e.weights.toSet().toList()..sort();
    return ws.isEmpty ? '400' : ws.map((w) => w.toString()).join(';');
  }

  final w = wght();
  if (!e.italic) {
    return v == null && e.weights.length <= 1
        ? 'family=$fam'
        : 'family=$fam:wght@$w';
  }
  return 'family=$fam:ital,wght@0,$w;1,$w';
}

/// The fallback stack after the family, derived from the category (the
/// corpus' own convention: serif displays fall to Georgia, sans to the
/// system rail).
String stackFor(FontCatalogEntry e) {
  final quoted = "'${e.family.replaceAll("'", r"\'")}'";
  switch (e.category.toLowerCase()) {
    case 'serif':
    case 'display':
      return '$quoted, Georgia, serif';
    case 'monospace':
      return '$quoted, ui-monospace, monospace';
    default:
      return "$quoted, 'Helvetica Neue', Arial, sans-serif";
  }
}

/// One generated override sheet: gates the role's token on the choice.
String fontSheetCss(FontRole role, FontChoice choice) {
  return '/* font choice ${role.id}/${choice.id} — generated by the font plane, do not hand-edit */\n[data-font-${role.id}="${choice.id}"] {\n  ${role.token}: ${choice.stack};\n}\n';
}

class FontIngestion {
  FontIngestion({required this.artifactDir});

  final String artifactDir;

  /// Append a catalog family to a role's choices (dedupe by family — the
  /// palette's swatch-set law): generates the sheet, extends fonts.json.
  /// Returns the (new or existing) choice. Author-only at the route.
  FontChoice ingest(String roleId, FontCatalogEntry entry) {
    final manifest = FontPlaneManifest.load(artifactDir);
    if (manifest == null) {
      throw ArgumentError('no fonts.json — the artifact declares no font plane');
    }
    final role = manifest.role(roleId);
    if (role == null) throw ArgumentError('unknown font role: $roleId');
    final id = fontChoiceId(entry.family);
    final existing = role.choice(id);
    if (existing != null) return existing;

    final choice = FontChoice(
      id: id,
      family: entry.family,
      stack: stackFor(entry),
      category: entry.category,
      css2: css2SegmentFor(entry),
      source: 'google:${entry.family}',
      sheet: '/assets/styles/fonts/font-$roleId-$id.css',
    );
    File(p.join(artifactDir, 'assets', 'styles', 'fonts',
            'font-$roleId-$id.css'))
        .createSync(recursive: true);
    File(p.join(artifactDir, 'assets', 'styles', 'fonts',
            'font-$roleId-$id.css'))
        .writeAsStringSync(fontSheetCss(role, choice));
    role.choices.add(choice);
    manifest.save(artifactDir);
    return choice;
  }

  /// Remove an ingested choice (seeded refuse — the palette delete law).
  /// A pick that still points here resolves to the default at serve time.
  List<FontRole> delete(String roleId, String choiceId) {
    final manifest = FontPlaneManifest.load(artifactDir);
    if (manifest == null) {
      throw ArgumentError('no fonts.json — the artifact declares no font plane');
    }
    final role = manifest.role(roleId);
    if (role == null) throw ArgumentError('unknown font role: $roleId');
    final choice = role.choice(choiceId);
    if (choice == null) throw ArgumentError('unknown choice: $choiceId');
    if (choice.seeded) {
      throw ArgumentError('seeded choices refuse deletion');
    }
    if (manifest.defaultPicks[roleId] == choiceId) {
      throw ArgumentError('the default choice refuses deletion');
    }
    role.choices.remove(choice);
    if (choice.sheet != null && choice.sheet!.startsWith('/')) {
      final f = File(p.join(artifactDir, choice.sheet!.substring(1)));
      if (f.existsSync()) f.deleteSync();
    }
    manifest.save(artifactDir);
    return manifest.roles;
  }
}

// ── the catalog (grilled Q3: server-fetched + trimmed) ───────────────────

class FontCatalog {
  FontCatalog._(this._families, this.fetchedAt);

  final List<FontCatalogEntry> _families;
  final DateTime fetchedAt;

  static File get _cacheFile => File(p.join(arxaHome(), 'font-catalog.json'));

  /// The trimmed cache from disk, or null when never fetched.
  static FontCatalog? loadCache() {
    try {
      if (!_cacheFile.existsSync()) return null;
      final parsed = jsonDecode(_cacheFile.readAsStringSync());
      if (parsed is! Map) return null;
      final fetched = parsed['fetchedAt'];
      final list = parsed['families'];
      if (fetched is! String || list is! List) return null;
      final fams = <FontCatalogEntry>[];
      for (final raw in list) {
        final e = FontCatalogEntry.fromJson(raw);
        if (e != null) fams.add(e);
      }
      return FontCatalog._(fams, DateTime.tryParse(fetched) ?? DateTime.now());
    } catch (_) {
      return null;
    }
  }

  /// Fetch Google's metadata feed server-side (the browser cannot — it is
  /// same-site-only), trim to the searchable fields for latin-capable
  /// non-Noto families, cache under ~/.arxa/font-catalog.json. Serves from
  /// the cache while fresh (staleAfter), so a booting design server never
  /// pays the feed unless it must.
  static Future<FontCatalog> fetch(
      {Duration staleAfter = const Duration(days: 7)}) async {
    final cached = loadCache();
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < staleAfter) {
      return cached;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client
          .getUrl(Uri.parse('https://fonts.google.com/metadata/fonts'));
      final res = await req.close().timeout(const Duration(seconds: 30));
      final text = await utf8.decoder.bind(res).join();
      if (res.statusCode >= 300) {
        throw StateError('catalog feed answered ${res.statusCode}');
      }
      final parsed = jsonDecode(text);
      if (parsed is! Map) {
        throw const FormatException('catalog feed not an object');
      }
      final list = parsed['familyMetadataList'];
      if (list is! List) {
        throw const FormatException('no familyMetadataList');
      }
      final fams = <FontCatalogEntry>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        if (raw['isNoto'] == true) continue; // skip the Noto wall
        final subsets = raw['subsets'];
        if (subsets is! List || !subsets.contains('latin')) continue;
        final family = raw['family'];
        final category = raw['category'];
        if (family is! String || category is! String) continue;
        // Variable weight range, when the family declares the wght axis.
        List<int>? variableWght;
        final axes = raw['axes'];
        if (axes is List) {
          for (final a in axes) {
            if (a is Map && a['tag'] == 'wght') {
              final min = a['min'], max = a['max'];
              if (min is num && max is num) {
                variableWght = [min.round(), max.round()];
              }
            }
          }
        }
        final styles = raw['fonts'];
        final italic = styles is List &&
            styles.any((s) => s is Map && (s['stylename'] ?? '') == 'Italic');
        final popularity = raw['popularity'];
        fams.add(FontCatalogEntry(
          family: family,
          category: category,
          weights: const [400],
          variableWght: variableWght ?? _staticWeights(styles),
          italic: italic,
          popularity: popularity is num ? popularity.round() : 0,
        ));
      }
      fams.sort((a, b) => b.popularity.compareTo(a.popularity));
      final catalog = FontCatalog._(fams, DateTime.now());
      _cacheFile.parent.createSync(recursive: true);
      _cacheFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
        'fetchedAt': catalog.fetchedAt.toIso8601String(),
        'families': [for (final e in fams) e.toJson()],
      }));
      return catalog;
    } finally {
      client.close(force: true);
    }
  }

  /// Google's feed gives static families a fonts[] array of per-style
  /// files; the weights come from the wght axis each carries.
  static List<int> _staticWeights(Object? styles) {
    if (styles is! List) return const [400];
    final ws = <int>{};
    for (final f in styles) {
      if (f is! Map) continue;
      final axes = f['axes'];
      if (axes is List) {
        for (final a in axes) {
          if (a is Map && a['tag'] == 'wght' && a['value'] is num) {
            ws.add((a['value'] as num).round());
          }
        }
      }
    }
    if (ws.isEmpty) return const [400];
    final list = ws.toList()..sort();
    return list;
  }

  /// Case-insensitive substring search, popularity-ranked, capped — the
  /// dropdown's source of truth. Empty query = the popular head.
  List<FontCatalogEntry> search(String q, {int limit = 60}) {
    final needle = q.trim().toLowerCase();
    final out = <FontCatalogEntry>[];
    for (final e in _families) {
      if (needle.isEmpty || e.family.toLowerCase().contains(needle)) {
        out.add(e);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  FontCatalogEntry? byFamily(String family) {
    for (final e in _families) {
      if (e.family.toLowerCase() == family.toLowerCase()) return e;
    }
    return null;
  }
}
