/// The Design Dial's axes plane (consolidation arc 1, grilled 2026-08-25):
/// style + theme selection is dial-owned and artifact-agnostic. The
/// artifact only DECLARES its axes in the served head —
///   `<link rel="stylesheet" ... data-axes-style="glass" [disabled]>`
///   `<html data-axes-themes="system light dark">`
/// and only when the nearest appbox.json marker (walk-up from the
/// artifact dir) says kind: app. Sites never see the control.
///
/// The server applies the active pick to every served full page:
///   ?style=/?theme= (per-request override: probes, guest previewing)
///   > the stored published pick > the shipped default (the one enabled
///   link; theme falls back to system = no data-theme, OS media bridges).
/// Guests never write the store — their flips ride the URL override, and
/// a persistent preview badge marks on-screen != published (the grilled
/// no-confusion law, research-backed: Storybook globals ride the URL;
/// CMS preview bars mark non-published state persistently).
///
/// Storage: Supabase (design_dial_axes keyed by the design's registered
/// id — project/artifact identity, never a bare basename: two clients
/// both shipping a design/ dir must not collide) behind the same
/// stale-while-revalidate + socket-timeout discipline as pins (the
/// 2026-08-25 brownout law: a Supabase stall must never hang a page
/// serve), with the honest per-process memory store when unconfigured.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'project.dart' show appboxHome;

/// The axis-value law: lowercase url-safe ids, bounded length. Shared by
/// the declaration parser, the serve-time override, and the POST route.
final axisValuePattern = RegExp(r'^[a-z0-9-]{1,40}$');

/// One resolved style/theme pair.
class AxesPick {
  const AxesPick({required this.style, required this.theme});

  final String style;
  final String theme;

  Map<String, String> toJson() => {'style': style, 'theme': theme};

  static AxesPick? fromJson(Object? json) {
    if (json is! Map) return null;
    final style = json['style'];
    final theme = json['theme'];
    if (style is! String || theme is! String) return null;
    if (!axisValuePattern.hasMatch(style) ||
        !axisValuePattern.hasMatch(theme)) {
      return null;
    }
    return AxesPick(style: style, theme: theme);
  }

  @override
  bool operator ==(Object other) =>
      other is AxesPick && other.style == style && other.theme == theme;

  @override
  int get hashCode => Object.hash(style, theme);
}

/// The artifact's pipeline identity, read from the appbox.json marker.
class ArtifactMarker {
  const ArtifactMarker({required this.project, required this.kind});

  /// The marker's `name` (e.g. energize-studio) — the project dimension
  /// every dial store key carries.
  final String project;

  /// The marker's `kind` — axes are a kind: app capability only.
  final String kind;
}

/// The appbox.json marker nearest the artifact dir (walk-up — the project
/// resolve law). Null = no marker = the dial offers no axes at all; a
/// malformed marker disables them the same way rather than guessing.
ArtifactMarker? resolveArtifactMarker(String artifactDir) {
  var dir = Directory(p.absolute(artifactDir));
  while (true) {
    final markerFile = File(p.join(dir.path, 'appbox.json'));
    if (markerFile.existsSync()) {
      try {
        final parsed = jsonDecode(markerFile.readAsStringSync());
        if (parsed is Map &&
            parsed['name'] is String &&
            parsed['kind'] is String) {
          return ArtifactMarker(
              project: parsed['name'] as String,
              kind: parsed['kind'] as String);
        }
      } catch (_) {
        // Fall through to null below.
      }
      return null;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

/// The dial's author, from ~/.appbox/identity.json ({"name","email"}).
/// Null never blocks a serve — the design registers unattributed and the
/// server says so on stderr once at boot.
class AuthorIdentity {
  const AuthorIdentity({required this.name, required this.email});

  final String name;
  final String email;
}

AuthorIdentity? loadAuthorIdentity({String? home}) {
  final identityFile = File(p.join(home ?? appboxHome(), 'identity.json'));
  try {
    if (!identityFile.existsSync()) return null;
    final parsed = jsonDecode(identityFile.readAsStringSync());
    if (parsed is Map && parsed['email'] is String) {
      return AuthorIdentity(
          name: (parsed['name'] as String?) ?? '',
          email: parsed['email'] as String);
    }
  } catch (_) {
    // An unreadable identity is unattributed, not a serve failure.
  }
  return null;
}

// ── the store ────────────────────────────────────────────────────────────

/// The published axes of ONE design (the server is per-artifact, so the
/// store binds the design at construction).
abstract class AxesStore {
  /// 'supabase' or 'memory' — the island badges the memory mode 'local'.
  String get kind;

  /// The published pick, or null when none has been stored (the shipped
  /// default then answers). Must never throw on a network stall — a page
  /// serve reads this on every request.
  Future<AxesPick?> load();

  /// Publish a pick. May throw — the API answers 502 honestly.
  Future<void> save(AxesPick pick);
}

/// The zero-config store: per-process. Correct for local solo use;
/// honest about resetting on restart.
class MemoryAxesStore implements AxesStore {
  AxesPick? _pick;

  @override
  String get kind => 'memory';

  @override
  Future<AxesPick?> load() async => _pick;

  @override
  Future<void> save(AxesPick pick) async {
    _pick = pick;
  }
}

/// Supabase-backed axes. Reads ride a short-TTL stale-while-revalidate
/// cache for the same reason pins do (2026-08-25: edge brownouts spiked
/// 1-5s mid-session; every served page reads axes, so an uncached read
/// would hold a browser socket per navigation). Writes upsert and update
/// the cache immediately — the author sees fresh truth after acting.
class SupabaseAxesStore implements AxesStore {
  SupabaseAxesStore({
    required this.url,
    required this.serviceKey,
    required this.project,
    required this.artifact,
    this.author,
  });

  final String url;
  final String serviceKey;
  final String project;
  final String artifact;
  final AuthorIdentity? author;

  /// Builds one from env or the credentials file text, or null when
  /// unconfigured. Mirrors SupabaseDialStore.fromConfig's precedence:
  /// env vars win, the file fills gaps.
  static SupabaseAxesStore? fromConfig({
    Map<String, String>? env,
    String? credentialsFileText,
    required String project,
    required String artifact,
    AuthorIdentity? author,
  }) {
    final environment = env ?? Platform.environment;
    var url = environment['APPBOX_SUPABASE_URL'];
    var key = environment['APPBOX_SUPABASE_SERVICE_KEY'];
    if ((url == null || url.isEmpty || key == null || key.isEmpty) &&
        credentialsFileText != null) {
      String? fileUrl;
      String? fileKey;
      for (final line in credentialsFileText.split('\n')) {
        final match = RegExp(r'^(url|service_key)=(.+)$')
            .firstMatch(line.trim());
        if (match == null) continue;
        if (match.group(1) == 'url') fileUrl = match.group(2)!.trim();
        if (match.group(1) == 'service_key') {
          fileKey = match.group(2)!.trim();
        }
      }
      url ??= fileUrl;
      key ??= fileKey;
    }
    if (url == null || url.isEmpty || key == null || key.isEmpty) {
      return null;
    }
    return SupabaseAxesStore(
        url: url,
        serviceKey: key,
        project: project,
        artifact: artifact,
        author: author);
  }

  // The dial's network discipline (design_dial.dart, measured 2026-08-25):
  // capped idle so a dropped pooled connection can never hang the next
  // request behind TCP retransmit backoff; timeouts + abort convert a
  // stall into a fast failure instead of a held browser socket.
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 30);

  static const Duration _cacheTtl = Duration(seconds: 5);
  AxesPick? _cache;
  DateTime? _cacheAt;
  String? _designId;

  Future<HttpClientResponse> _request(String method, String path,
      {Object? body, Map<String, String>? extraHeaders}) async {
    final request = await _http
        .openUrl(method, Uri.parse('$url/rest/v1/$path'))
        .timeout(const Duration(seconds: 8));
    request.headers.set('apikey', serviceKey);
    request.headers.set('Authorization', 'Bearer $serviceKey');
    extraHeaders?.forEach(request.headers.set);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    try {
      return await request.close().timeout(const Duration(seconds: 10));
    } on TimeoutException {
      request.abort();
      rethrow;
    }
  }

  /// The design's registered id, minted on first use: upsert on
  /// (project, artifact) so re-serves and sibling processes converge on
  /// one row — never a basename key.
  Future<String> _ensureDesignId() async {
    final known = _designId;
    if (known != null) return known;
    // INSERT, and on the natural-key conflict read the row back. This
    // PostgREST does NOT infer the (project, artifact) unique constraint
    // for upsert conflict resolution - measured live 2026-08-26:
    // merge-duplicates AND ignore-duplicates both answer 23505 on an
    // existing row, so the upsert is a plain 409 here. The fallback GET
    // is deterministic (the row provably exists - that is why we got
    // the 409); the only race is two first-boots inserting at once, and
    // the loser lands in the GET.
    final response = await _request('POST', 'design_dial_designs', body: {
      'project': project,
      'artifact': artifact,
      if (author != null) 'author_email': author!.email,
      if (author != null) 'author_name': author!.name,
    }, extraHeaders: {
      'Prefer': 'return=representation'
    });
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode == 409) {
      final get = await _request(
          'GET',
          'design_dial_designs?project=eq.${Uri.encodeComponent(project)}'
              '&artifact=eq.${Uri.encodeComponent(artifact)}'
              '&select=id');
      final getText = await utf8.decoder.bind(get).join();
      if (get.statusCode >= 300) {
        throw StateError('design lookup failed (${get.statusCode}): $getText');
      }
      final found = jsonDecode(getText);
      if (found is List && found.isNotEmpty && found.first is Map) {
        final existing = (found.first as Map)['id'];
        if (existing is String) {
          _designId = existing;
          return existing;
        }
      }
      throw StateError('design 409 but no row reads back: $getText');
    }
    if (response.statusCode >= 300) {
      throw StateError(
          'design registration failed (${response.statusCode}): $text');
    }
    final rows = jsonDecode(text);
    if (rows is! List || rows.isEmpty || rows.first is! Map) {
      throw StateError('design registration returned no row: $text');
    }
    final id = (rows.first as Map)['id'];
    if (id is! String) {
      throw StateError('design registration returned no id: $text');
    }
    _designId = id;
    return id;
  }

  Future<AxesPick?> _fetch() async {
    final designId = await _ensureDesignId();
    final response = await _request(
        'GET', 'design_dial_axes?design_id=eq.$designId&select=style,theme');
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode >= 300) {
      throw StateError('axes read failed (${response.statusCode}): $text');
    }
    final rows = jsonDecode(text);
    if (rows is! List || rows.isEmpty) return null;
    return AxesPick.fromJson(rows.first);
  }

  Future<void> _refresh() async {
    try {
      final pick = await _fetch();
      _cache = pick;
      _cacheAt = DateTime.now();
    } catch (error) {
      // A read failure must never break a serve: keep the last answer
      // (or none), say so once per attempt, and let the next request
      // retry.
      stderr.writeln('[design-server] dial axes read failed: $error');
    }
  }

  @override
  Future<AxesPick?> load() async {
    final at = _cacheAt;
    if (at != null && DateTime.now().difference(at) < _cacheTtl) {
      return _cache;
    }
    if (at != null) {
      // Stale-while-revalidate: answer now, refresh in the background.
      unawaited(_refresh());
      return _cache;
    }
    // Truly cold: pay the network once so the first serve is correct.
    await _refresh();
    return _cache;
  }

  @override
  Future<void> save(AxesPick pick) async {
    final designId = await _ensureDesignId();
    final response = await _request('POST', 'design_dial_axes', body: {
      'design_id': designId,
      'style': pick.style,
      'theme': pick.theme,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, extraHeaders: {
      'Prefer': 'resolution=merge-duplicates'
    });
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode >= 300) {
      throw StateError('axes write failed (${response.statusCode}): $text');
    }
    _cache = pick;
    _cacheAt = DateTime.now();
  }

  @override
  String get kind => 'supabase';
}

// ── the serve-time machinery (pure: html in, html + config out) ─────────

/// What an artifact declares in its served head.
class AxesDeclaration {
  const AxesDeclaration({
    required this.styles,
    required this.themes,
    required this.defaultStyle,
  });

  /// Declared style ids in document order.
  final List<String> styles;

  /// Declared theme ids; empty = the artifact has no theme axis.
  final List<String> themes;

  /// The style the artifact ships enabled — the published default when
   /// the store holds no pick.
  final String defaultStyle;
}

final _styleLinkPattern =
    RegExp(r'<link\b[^>]*\bdata-axes-style="([^"]+)"[^>]*>');
final _htmlTagPattern = RegExp(r'<html\b[^>]*>');
final _themesAttrPattern = RegExp(r'\bdata-axes-themes="([^"]*)"');
final _themeAttrPattern = RegExp(r'\s+data-theme="[^"]*"');
final _disabledAttrPattern = RegExp(r'\s+disabled(="[^"]*")?');

/// Parse the declaration. Null = the artifact declares nothing = the dial
/// offers no axes and the serve passes through untouched.
AxesDeclaration? parseAxesDeclaration(String html) {
  final links = _styleLinkPattern.allMatches(html).toList();
  if (links.isEmpty) return null;
  final styles = <String>[];
  String? shippedDefault;
  for (final match in links) {
    final id = match.group(1)!;
    if (axisValuePattern.hasMatch(id)) styles.add(id);
    if (shippedDefault == null &&
        !_disabledAttrPattern.hasMatch(match.group(0)!)) {
      shippedDefault = id;
    }
  }
  if (styles.isEmpty) return null;
  final htmlTag = _htmlTagPattern.firstMatch(html)?.group(0) ?? '';
  final themesRaw = _themesAttrPattern.firstMatch(htmlTag)?.group(1) ?? '';
  final themes = themesRaw
      .split(RegExp(r'\s+'))
      .where(axisValuePattern.hasMatch)
      .toList();
  return AxesDeclaration(
      styles: styles,
      themes: themes,
      defaultStyle: shippedDefault ?? styles.first);
}

/// The result of applying axes to one served page.
class ServedAxes {
  const ServedAxes({
    required this.html,
    required this.config,
    required this.active,
    required this.published,
  });

  /// The page with the active style's link enabled (all others disabled)
  /// and data-theme set or stripped on the `<html>` tag.
  final String html;

  /// The island's axes block: declaration + both picks, so the dial can
  /// render the control and mark previewing != published.
  final Map<String, Object?> config;

  /// What this page renders (override > published > default).
  final AxesPick active;

  /// What the store publishes (or the shipped default).
  final AxesPick published;
}

/// Resolve and apply the axes for one served page. Precedence per axis:
/// a VALID query override beats the stored pick beats the shipped
/// default; invalid or undeclared values fall through silently — a probe
/// pointing at a removed style gets the default, not a crash. Null when
/// the page declares no axes.
ServedAxes? applyAxesToServedHtml(
  String html, {
  required Map<String, String> query,
  required AxesPick? stored,
}) {
  final declaration = parseAxesDeclaration(html);
  if (declaration == null) return null;

  final defaultTheme = declaration.themes.contains('system')
      ? 'system'
      : (declaration.themes.isEmpty ? 'system' : declaration.themes.first);
  String resolve(String? overrideValue, String? storedValue,
      String fallback, List<String> allowed) {
    if (overrideValue != null && allowed.contains(overrideValue)) {
      return overrideValue;
    }
    if (storedValue != null && allowed.contains(storedValue)) {
      return storedValue;
    }
    return fallback;
  }

  final published = AxesPick(
    style: resolve(
        null, stored?.style, declaration.defaultStyle, declaration.styles),
    theme: resolve(null, stored?.theme, defaultTheme, declaration.themes),
  );
  final active = AxesPick(
    style: resolve(query['style'], stored?.style,
        declaration.defaultStyle, declaration.styles),
    theme:
        resolve(query['theme'], stored?.theme, defaultTheme, declaration.themes),
  );

  var out = html;
  for (final match in _styleLinkPattern.allMatches(html)) {
    final tag = match.group(0)!;
    final id = match.group(1)!;
    final stripped = tag.replaceAll(_disabledAttrPattern, '');
    final selfClosed = stripped.endsWith('/>');
    final core =
        stripped.substring(0, stripped.length - (selfClosed ? 2 : 1));
    final next = core +
        (id == active.style ? '' : ' disabled') +
        (selfClosed ? '/>' : '>');
    if (next != tag) out = out.replaceFirst(tag, next);
  }
  final htmlMatch = _htmlTagPattern.firstMatch(out);
  if (htmlMatch != null) {
    final tag = htmlMatch.group(0)!;
    final stripped = tag.replaceAll(_themeAttrPattern, '');
    final selfClosed = stripped.endsWith('/>');
    final core =
        stripped.substring(0, stripped.length - (selfClosed ? 2 : 1));
    final showTheme =
        declaration.themes.isNotEmpty && active.theme != 'system';
    final next = core +
        (showTheme ? ' data-theme="${active.theme}"' : '') +
        (selfClosed ? '/>' : '>');
    if (next != tag) out = out.replaceFirst(tag, next);
  }

  return ServedAxes(
    html: out,
    active: active,
    published: published,
    config: {
      'styles': declaration.styles,
      'themes': declaration.themes,
      'active': active.toJson(),
      'published': published.toJson(),
    },
  );
}
