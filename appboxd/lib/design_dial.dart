/// The Design Dial's server core — Feedback Mode slice (locked amendment
/// 2026-08-23, rust-port-closure-and-surgical-lens.md 'the feedback dial
/// becomes the Design Dial').
///
/// WHAT LIVES HERE. Everything the dial needs that is NOT the island: the
/// pin/share-link domain model, the kanban vocabulary, validation, and the
/// store seam. The request-handling core (DialApi.handle) is a pure
/// function over (method, path, json, caller) so the whole API is testable
/// without booting an HTTP server; design_server.dart holds only the thin
/// adapter.
///
/// THE STORE SEAM. Two stores:
///   * MemoryDialStore — per-process, the default when no Supabase env is
///     present. Keeps the dial usable in a bare design serve (Michelle's
///     20-minute eval must not require a Supabase account). Pins die with
///     the process and the island says so ('local' badge).
///   * SupabaseDialStore — PostgREST against the operator-owned central
///     project (locked: 'central Supabase stands'). Env:
///     APPBOX_SUPABASE_URL + APPBOX_SUPABASE_SERVICE_KEY. The service key
///     never leaves the server — clients (guest or author) talk ONLY to
///     this server / the deployed Worker, never to Supabase directly, so
///     the RLS posture is 'enabled, service-role only, no anon policies'.
///
/// WHO MAY WHAT (locked decisions 1/7/9). The loopback server IS the Author
/// (browser_trust.dart's threat model); a caller carrying a valid share
/// token is a guest. Guests create pins and replies; kanban moves and share
/// minting are Author-only.
///
/// REALTIME. This server broadcasts its own writes over /__dial/events
/// (SSE). Cross-runtime delivery (a guest pinning on the deployed Worker
/// showing up in the local session) needs Supabase realtime or polling —
/// that lands with the Publish slice.
library;

import 'design_media.dart';
import 'design_ship.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;

import 'design_draft.dart';
import 'design_patch.dart' show nameSiteLocations;

// ── vocabulary ───────────────────────────────────────────────────────────

/// The pin lifecycle (rework 2026-08-24, operator): design review needs
/// exactly live / settled / refused. triaged and in_progress were
/// project-management states, not review states — they die here, and old
/// rows fold to open on read (a pin that was triaged or in progress but
/// never resolved IS still open).
enum DialPinStatus {
  open('open'),
  resolved('resolved'),
  wontDo('wont_do');

  const DialPinStatus(this.wire);
  final String wire;

  static DialPinStatus? parse(String? s) {
    if (s == 'triaged' || s == 'in_progress') return DialPinStatus.open;
    for (final v in values) {
      if (v.wire == s) return v;
    }
    return null;
  }
}

/// Who is talking. 'author' is the design's one Author; 'guest' arrived via
/// a Share Link. Never raw strings at the call sites.
enum DialCaller { author, guest }

// ── model ────────────────────────────────────────────────────────────────

class DialReply {
  DialReply({
    required this.id,
    required this.authorKind,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final DialCaller authorKind;
  final String authorName;
  final String body;
  final String createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'author': authorKind.name,
        'name': authorName,
        'body': body,
        'createdAt': createdAt,
      };
}

class DialPin {
  DialPin({
    required this.id,
    required this.artifact,
    required this.route,
    required this.viewportW,
    required this.viewportH,
    required this.anchorEl,
    required this.rect,
    required this.status,
    required this.authorKind,
    required this.authorName,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.drawing,
    this.contextText,
    List<DialReply>? replies,
  }) : replies = replies ?? [];

  final String id;
  final String artifact;
  final String route;
  final int viewportW;
  final int viewportH;

  /// The W7 data-el identity the pin binds to (null = surface-level pin
  /// on the body sentinel). The rect snapshot is always stored so a removed
  /// element leaves an Orphaned Pin at its last known position (decision 6).
  final String? anchorEl;

  /// {x, y, w, h} in page coordinates at pin time.
  final Map<String, double> rect;

  /// The strokes the author drew while placing this pin (locked 2026-08-23:
  /// drawings attach to pins — the pub.dev feedback model; a drawing
  /// never exists standalone. MemoryDialStore carries it on the pin;
  /// SupabaseDialStore persists it as a design_dial_drawings row (1:1,
  /// storage amendment 2026-08-23). Shape: strokes → points → [x, y] page
  /// coordinates. Null when the pin carries no drawing.
  final List<List<List<double>>>? drawing;

  /// The anchored element's text snapshot at pin time (≤600 chars;
  /// research slice 2026-08-25 — Figma design-context practice: a comment
  /// bound to CONTENT survives copy edits and orphaning, not just to a
  /// rect). Null for surface pins and pre-column pins.
  final String? contextText;

  DialPinStatus status;
  final DialCaller authorKind;
  final String authorName;
  final String body;
  final String createdAt;
  String updatedAt;
  final List<DialReply> replies;

  Map<String, dynamic> toJson() => {
        'id': id,
        'artifact': artifact,
        'route': route,
        'viewport': {'w': viewportW, 'h': viewportH},
        'anchor': {
          'el': anchorEl,
          'rect': rect,
          if (contextText != null) 'text': contextText,
        },
        if (drawing != null) 'drawing': drawing,
        'status': status.wire,
        'author': authorKind.name,
        'name': authorName,
        'body': body,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'replies': [for (final r in replies) r.toJson()],
      };
}

/// A resolved Share Link grant (locked decision 7): scoped to one artifact,
/// expiring, comment-level permission only.
class ShareLinkGrant {
  const ShareLinkGrant({
    required this.artifact,
    required this.expiresAt,
  });

  final String artifact;

  /// ISO-8601; null never expires (operator choice, not the default).
  final String? expiresAt;

  bool get expired {
    if (expiresAt == null) return false;
    final at = DateTime.tryParse(expiresAt!);
    return at == null || DateTime.now().toUtc().isAfter(at);
  }
}

// ── store seam ───────────────────────────────────────────────────────────

abstract class DialStore {
  /// 'supabase' or 'memory' — the island badges the memory mode 'local'.
  String get kind;

  Future<List<DialPin>> listPins(String artifact, {String? route});
  Future<DialPin> createPin(DialPin pin);

  /// Returns null when the id is unknown.
  Future<DialPin?> setStatus(String id, DialPinStatus status);
  Future<DialReply?> addReply(
      String pinId, DialCaller kind, String name, String body);

  /// Mints a Share Link: returns the RAW token (shown once, stored hashed).
  Future<String> mintShareLink(String artifact, Duration ttl);
  Future<ShareLinkGrant?> resolveShareLink(String token);
}

String dialNewId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
      '-${h.substring(16, 20)}-${h.substring(20)}';
}

String _hashToken(String raw) => sha256.convert(ascii.encode(raw)).toString();

String _mintToken() {
  final r = Random.secure();
  final b = List<int>.generate(32, (_) => r.nextInt(256));
  return base64Url.encode(b).replaceAll('=', '');
}

/// The zero-config store. Correct for local solo use; honest about it.
class MemoryDialStore implements DialStore {
  final _pins = <String, DialPin>{};

  /// sha256(token) → grant.
  final _links = <String, ShareLinkGrant>{};

  @override
  String get kind => 'memory';

  @override
  Future<List<DialPin>> listPins(String artifact, {String? route}) async {
    final out = _pins.values
        .where((pin) =>
            pin.artifact == artifact && (route == null || pin.route == route))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  @override
  Future<DialPin> createPin(DialPin pin) async {
    _pins[pin.id] = pin;
    return pin;
  }

  @override
  Future<DialPin?> setStatus(String id, DialPinStatus status) async {
    final pin = _pins[id];
    if (pin == null) return null;
    pin.status = status;
    pin.updatedAt = DateTime.now().toUtc().toIso8601String();
    return pin;
  }

  @override
  Future<DialReply?> addReply(
      String pinId, DialCaller kind, String name, String body) async {
    final pin = _pins[pinId];
    if (pin == null) return null;
    final reply = DialReply(
      id: dialNewId(),
      authorKind: kind,
      authorName: name,
      body: body,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    pin.replies.add(reply);
    pin.updatedAt = reply.createdAt;
    return reply;
  }

  @override
  Future<String> mintShareLink(String artifact, Duration ttl) async {
    final raw = _mintToken();
    _links[_hashToken(raw)] = ShareLinkGrant(
      artifact: artifact,
      expiresAt: DateTime.now().toUtc().add(ttl).toIso8601String(),
    );
    return raw;
  }

  @override
  Future<ShareLinkGrant?> resolveShareLink(String token) async {
    final grant = _links[_hashToken(token)];
    if (grant == null || grant.expired) return null;
    return grant;
  }
}

/// PostgREST against the operator-owned central project. Table shapes are
/// the migration in supabase/migrations/20260823_design_dial.sql — keep them
/// in lockstep. One HttpClient per store; no pooling beyond dart:io's own.
class SupabaseDialStore implements DialStore {
  SupabaseDialStore({required this.url, required this.serviceKey});

  final String url;
  final String serviceKey;

  // The dial's network hop must never hang a browser socket. Without an
  // idle cap, dart:io pools connections that Supabase's edge silently drops
  // (NAT/idle timeout), and the next request on the corpse waits out TCP
  // retransmit backoff — seconds to minutes. Measured 2026-08-25 as the
  // frozen-app session: the panel's pins polls each hung on a dead pooled
  // connection and held the browser's 6-socket per-origin pool (one more
  // seat taken by the dial SSE) until every navigation queued behind them;
  // the app went unresponsive and landed on the user's LAST click only when
  // TCP gave up. Fresh connections (curl, lens Chrome) never saw it — only
  // the pooled panel path did. The timeouts convert that hang into a fast
  // 5xx; the idle cap retires connections before the edge drops them.
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 30);

  // Pins reads are the hot path: EVERY served page's dial island boots with
  // one, and the handler holds the browser's fetch socket for the full
  // Supabase latency. During an edge brownout (measured 2026-08-25: 1–5s
  // spikes, minutes apart) rapid page loads stacked those slow reads until
  // the browser's 6-socket per-origin pool saturated and the NEXT navigation
  // queued behind them — the app froze and landed on the user's last click
  // when the brownout eased. Reads therefore answer from a short-TTL cache
  // (stale-while-revalidate): the panel gets sub-millisecond answers, the
  // remote refreshes in the background, and mutations invalidate so every
  // author sees fresh truth immediately after acting.
  static const Duration _pinsTtl = Duration(seconds: 5);
  final _pinsCache = <String, List<DialPin>>{};
  final _pinsCacheAt = <String, DateTime>{};
  final _pinsRefreshing = <String>{};

  @override
  String get kind => 'supabase';

  /// Builds one from configuration, or null when unconfigured (caller falls
  /// back to MemoryDialStore). The service key is server-side only — never
  /// log it.
  ///
  /// Precedence (env wins, so a one-shot override never edits a file):
  ///   1. APPBOX_SUPABASE_URL + APPBOX_SUPABASE_SERVICE_KEY in the process env
  ///   2. the machine-scoped file ~/.appbox/supabase — key=value lines
  ///      (url= / service_key=), '#' comments, same convention as
  ///      ~/.appbox/trusted-origins: an operator fact about THIS machine,
  ///      never repo state, never the artifact's config.
  static SupabaseDialStore? fromConfig(
      {Map<String, String>? env, String? credentialsFileText}) {
    final e = env ?? Platform.environment;
    var url = e['APPBOX_SUPABASE_URL'];
    var key = e['APPBOX_SUPABASE_SERVICE_KEY'];
    if ((url == null || url.isEmpty || key == null || key.isEmpty) &&
        credentialsFileText != null) {
      final file = parseSupabaseCredentials(credentialsFileText);
      url ??= file.url;
      key ??= file.key;
    }
    if (url == null || url.isEmpty || key == null || key.isEmpty) return null;
    return SupabaseDialStore(url: url, serviceKey: key);
  }

  /// Builds one from env, or null when unconfigured. Prefer [fromConfig] —
  /// this remains for callers that deliberately want env only.
  static SupabaseDialStore? fromEnv([Map<String, String>? env]) {
    return fromConfig(env: env);
  }

  Future<HttpClientResponse> _req(String method, String path,
      {Object? body, Map<String, String>? extraHeaders}) async {
    final req = await _http
        .openUrl(method, Uri.parse('$url/rest/v1/$path'))
        .timeout(const Duration(seconds: 8));
    req.headers.set('apikey', serviceKey);
    req.headers.set('Authorization', 'Bearer $serviceKey');
    extraHeaders?.forEach(req.headers.set);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    try {
      return await req.close().timeout(const Duration(seconds: 10));
    } on TimeoutException {
      // Abort frees the socket AND discards the pooled connection — a
      // timed-out dial call must answer fast, never hold a browser socket
      // hostage while TCP retries a corpse.
      req.abort();
      rethrow;
    }
  }

  static Map<String, dynamic> _pinRow(DialPin p) => {
        'id': p.id,
        'artifact': p.artifact,
        'route': p.route,
        'viewport_w': p.viewportW,
        'viewport_h': p.viewportH,
        'anchor_el': p.anchorEl,
        'rect': p.rect,
        'context_text': p.contextText,
        'status': p.status.wire,
        'author_kind': p.authorKind.name,
        'author_name': p.authorName,
        'body': p.body,
        'created_at': p.createdAt,
        'updated_at': p.updatedAt,
      };

  /// The embedded design_dial_drawings row: a one-to-one object when
  /// PostgREST detects the unique FK, a list when it doesn't, null when the
  /// pin carries no drawing. Returns the strokes payload for asDrawing.
  static Object? _embeddedStrokes(Object? v) {
    if (v is Map) return v['strokes'];
    if (v is List && v.isNotEmpty) return (v.first as Map)['strokes'];
    return null;
  }

  static DialPin _pinFromRow(Map<String, dynamic> r, [List<DialReply>? rp]) =>
      DialPin(
        drawing: asDrawing(_embeddedStrokes(r['design_dial_drawings'])),
        id: r['id'] as String,
        artifact: r['artifact'] as String,
        route: r['route'] as String,
        viewportW: r['viewport_w'] as int,
        viewportH: r['viewport_h'] as int,
        anchorEl: r['anchor_el'] as String?,
        contextText: r['context_text'] as String?,
        rect: (r['rect'] as Map)
            .map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        status: DialPinStatus.parse(r['status'] as String)!,
        authorKind:
            r['author_kind'] == 'guest' ? DialCaller.guest : DialCaller.author,
        authorName: r['author_name'] as String,
        body: r['body'] as String,
        createdAt: r['created_at'] as String,
        updatedAt: r['updated_at'] as String,
        replies: rp,
      );

  static DialReply _replyFromRow(Map<String, dynamic> rr) => DialReply(
        id: rr['id'] as String,
        authorKind: rr['author_kind'] == 'guest'
            ? DialCaller.guest
            : DialCaller.author,
        authorName: rr['author_name'] as String,
        body: rr['body'] as String,
        createdAt: rr['created_at'] as String,
      );

  List<DialPin> _pinsFromResponse(Object body) {
    final rows = body as List;
    return [
      for (final r in rows)
        _pinFromRow(r as Map<String, dynamic>, [
          for (final rr
              in (r['design_dial_replies'] as List? ?? const []))
            _replyFromRow(rr as Map<String, dynamic>),
        ]),
    ];
  }

  Future<List<DialPin>> _fetchPins(String key, String q) async {
    final res = await _req('GET', q);
    return _pinsFromResponse(
        jsonDecode(await res.transform(utf8.decoder).join()));
  }

  @override
  Future<List<DialPin>> listPins(String artifact, {String? route}) async {
    var q = 'design_dial_pins?artifact=eq.${Uri.encodeComponent(artifact)}'
        '&order=created_at.asc'
        '&select=*,design_dial_replies(*),design_dial_drawings(strokes)';
    if (route != null) q += '&route=eq.${Uri.encodeComponent(route)}';
    final key = '$artifact|${route ?? ''}';
    final at = _pinsCacheAt[key];
    final fresh = at != null && DateTime.now().difference(at) < _pinsTtl;
    final cached = _pinsCache[key];
    if (fresh && cached != null) return cached;
    // Stale-while-revalidate: answer from cache NOW, refresh in the
    // background — the browser socket is released in microseconds either
    // way. Only a truly cold cache pays the network on the caller's socket.
    if (cached != null) {
      if (_pinsRefreshing.add(key)) {
        _fetchPins(key, q)
            .then((v) {
              _pinsCache[key] = v;
              _pinsCacheAt[key] = DateTime.now();
            })
            .whenComplete(() => _pinsRefreshing.remove(key));
      }
      return cached;
    }
    final v = await _fetchPins(key, q);
    _pinsCache[key] = v;
    _pinsCacheAt[key] = DateTime.now();
    return v;
  }

  void _invalidatePins() {
    _pinsCache.clear();
    _pinsCacheAt.clear();
  }

  @override
  Future<DialPin> createPin(DialPin pin) async {
    await _req('POST', 'design_dial_pins',
        body: _pinRow(pin), extraHeaders: {'Prefer': 'return=minimal'});
    final drawing = pin.drawing;
    if (drawing != null) {
      final res = await _req('POST', 'design_dial_drawings',
          body: {'pin_id': pin.id, 'strokes': drawing},
          extraHeaders: {'Prefer': 'return=minimal'});
      if (res.statusCode >= 400) {
        throw StateError(
            'design_dial_drawings insert failed: HTTP ${res.statusCode}');
      }
    }
    _invalidatePins();
    return pin;
  }

  @override
  Future<DialPin?> setStatus(String id, DialPinStatus status) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final res = await _req(
        'PATCH',
        'design_dial_pins?id=eq.${Uri.encodeComponent(id)}'
        '&select=*,design_dial_drawings(strokes)',
        body: {'status': status.wire, 'updated_at': now},
        extraHeaders: {'Prefer': 'return=representation'});
    final rows = jsonDecode(await res.transform(utf8.decoder).join()) as List;
    if (rows.isEmpty) return null;
    _invalidatePins();
    return _pinFromRow(rows.first as Map<String, dynamic>);
  }

  @override
  Future<DialReply?> addReply(
      String pinId, DialCaller kind, String name, String body) async {
    final reply = DialReply(
      id: dialNewId(),
      authorKind: kind,
      authorName: name,
      body: body,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    final res = await _req('POST', 'design_dial_replies',
        body: {
          'id': reply.id,
          'pin_id': pinId,
          'author_kind': kind.name,
          'author_name': name,
          'body': body,
          'created_at': reply.createdAt,
        },
        extraHeaders: {'Prefer': 'return=minimal'});
    if (res.statusCode >= 400) return null;
    _invalidatePins();
    return reply;
  }

  @override
  Future<String> mintShareLink(String artifact, Duration ttl) async {
    final raw = _mintToken();
    await _req('POST', 'design_dial_share_links',
        body: {
          'token_hash': _hashToken(raw),
          'artifact': artifact,
          'expires_at': DateTime.now().toUtc().add(ttl).toIso8601String(),
        },
        extraHeaders: {'Prefer': 'return=minimal'});
    return raw;
  }

  @override
  Future<ShareLinkGrant?> resolveShareLink(String token) async {
    final res = await _req(
        'GET',
        'design_dial_share_links?token_hash=eq.${_hashToken(token)}'
            '&select=artifact,expires_at');
    final rows = jsonDecode(await res.transform(utf8.decoder).join()) as List;
    if (rows.isEmpty) return null;
    final grant = ShareLinkGrant(
      artifact: rows.first['artifact'] as String,
      expiresAt: rows.first['expires_at'] as String?,
    );
    return grant.expired ? null : grant;
  }
}

/// The ~/.appbox/supabase file, parsed. A line that is not key=value is
/// dropped, not fatal — a half-written credentials file must degrade to the
/// memory store, not crash the server boot.
({String? url, String? key}) parseSupabaseCredentials(String text) {
  String? url;
  String? key;
  for (final raw in text.split('\n')) {
    final line = raw.split('#').first.trim();
    if (line.isEmpty) continue;
    final eq = line.indexOf('=');
    if (eq < 1) continue;
    final k = line.substring(0, eq).trim();
    final v = line.substring(eq + 1).trim();
    if (k == 'url') url = v;
    // The shipped file carries a placeholder until the operator pastes the
    // service_role key — treat it as absent so the dial degrades to the
    // memory store instead of booting a store whose every call 401s.
    if (k == 'service_key' && !v.startsWith('PASTE-')) key = v;
  }
  return (url: url, key: key);
}

/// Validates/converts a drawing payload: strokes → points → [x, y] finite
/// doubles, page coordinates. Returns null for a null/absent drawing; throws
/// FormatException for a malformed or oversized one. Caps (64 strokes, 2000
/// points per stroke, 8000 total) keep a hostile or runaway canvas from
/// landing a megabyte blob in the row.
List<List<List<double>>>? asDrawing(Object? v) {
  if (v == null) return null;
  if (v is! List) throw const FormatException('drawing must be an array');
  if (v.length > 64) throw const FormatException('drawing exceeds 64 strokes');
  var total = 0;
  final out = <List<List<double>>>[];
  for (final stroke in v) {
    if (stroke is! List || stroke.isEmpty) {
      throw const FormatException('each stroke must be a non-empty array');
    }
    if (stroke.length > 2000) {
      throw const FormatException('a stroke exceeds 2000 points');
    }
    total += stroke.length;
    if (total > 8000) {
      throw const FormatException('drawing exceeds 8000 points total');
    }
    final pts = <List<double>>[];
    for (final pt in stroke) {
      if (pt is! List || pt.length != 2) {
        throw const FormatException('each point must be [x, y]');
      }
      final x =
          pt[0] is num ? (pt[0] as num).toDouble() : double.tryParse('${pt[0]}');
      final y =
          pt[1] is num ? (pt[1] as num).toDouble() : double.tryParse('${pt[1]}');
      if (x == null || y == null || !x.isFinite || !y.isFinite) {
        throw const FormatException('point coordinates must be finite numbers');
      }
      pts.add([x, y]);
    }
    out.add(pts);
  }
  return out;
}

// ── the pure request core ────────────────────────────────────────────────

class DialResponse {
  const DialResponse(this.status, this.json);
  final int status;
  final Object json;
}

/// Validation caps. Loose enough never to bite real use, tight enough that
/// a pasted novel or a hostile blob cannot sit in the store.
abstract class _Caps {
  static const body = 4000;
  static const name = 80;
  static const route = 200;
  static const el = 200;
  static const context = 600;
}

/// The /__dial/* API as a pure function: no HttpRequest, no IO — the server
/// adapter (design_server.dart) reads the body and passes it here.
class DialApi {
  DialApi(
      {required this.store,
      required this.artifact,
      this.draftStore,
      this.artifactDir,
      this.media,
      this.ship});

  final DialStore store;

  /// The artifact identity pins and links scope to (artifact dir basename).
  final String artifact;

  /// The Draft Overlay's file store (decisions 5/11: local-server state,
  /// never Supabase). Null disables the draft/commit routes (503).
  final DraftFileStore? draftStore;

  /// The artifact's absolute dir — reported by /commit so the studio agent
  /// knows where to run `appbox design patch`.
  final String? artifactDir;

  /// The media proxy (slice 4, 2026-08-24): server-side Unsplash/Pexels
  /// search + copy-into-artifact. Null disables the routes (503).
  final DialMediaProxy? media;

  /// The Ship channel (slice 5, 2026-08-24): confined git+gh. Author-only;
  /// null (not a git repo) disables the routes (503).
  final DialShip? ship;

  /// Selection handoff registry (slice 7, 2026-08-24): the card's "Ask
  /// arxa" registers an organized selection context here; the studio agent
  /// fetches it by pointer id. Bounded: capped, TTL'd, author-only writes.
  final Map<String, (DateTime, Map<String, dynamic>)> _selections = {};

  /// [grant] non-null means the caller arrived on a Share Link — a guest
  /// scoped to ITS artifact (a link minted for artifact A reads nothing on
  /// artifact B). Null grant = the loopback Author.
  Future<DialResponse> handle(
    String method,
    String sub, // path after /__dial, no query
    Map<String, String> query,
    Object? body,
    ShareLinkGrant? grant,
  ) async {
    final caller = grant == null ? DialCaller.author : DialCaller.guest;
    if (grant != null && grant.artifact != artifact) {
      return const DialResponse(403, {'error': 'share link scopes elsewhere'});
    }
    if (grant == null && query['dial'] != null) {
      // A ?dial= token that resolves to nothing is a DEAD link, not the
      // Author — the island boots 'invalid' and says so, and the API
      // refuses. (Before the Design Mode routes this gap let a dead token
      // move the kanban as 'author'.)
      return const DialResponse(403, {'error': 'share link is dead'});
    }
    try {
      if (method == 'GET' && sub == '/pins') {
        return await _listPins();
      }
      if (method == 'POST' && sub == '/pins') {
        return await _createPin(body, caller);
      }
      if (method == 'POST' && sub == '/pins/status') {
        if (caller != DialCaller.author) {
          return const DialResponse(403, {'error': 'author only'});
        }
        return await _setStatus(body);
      }
      if (method == 'POST' && sub == '/pins/reply') {
        return await _reply(body, caller);
      }
      if (method == 'POST' && sub == '/share') {
        if (caller != DialCaller.author) {
          return const DialResponse(403, {'error': 'author only'});
        }
        return await _share(body);
      }
      // The Draft Overlay (Design Mode; decisions 5/11). Author-only: the
      // draft is the Author's uncommitted WIP — guests are served the last
      // published state and never see it.
      if (sub == '/draft') {
        if (caller != DialCaller.author) {
          return const DialResponse(403, {'error': 'author only'});
        }
        if (method == 'GET') return await _getDraft();
        if (method == 'PUT') return await _putDraft(body);
        if (method == 'DELETE') return await _clearDraft();
      }
      if (method == 'POST' && sub == '/commit') {
        if (caller != DialCaller.author) {
          return const DialResponse(403, {'error': 'author only'});
        }
        return await _commitDraft();
      }
      // The media proxy (slice 4): author-only — provider keys are
      // server-held secrets and the artifact tree is the author's.
      if (sub == '/media/search' && method == 'POST') {
        if (caller != DialCaller.author) {
          return const DialResponse(403, {'error': 'author only'});
        }
        return await _mediaSearch(body);
      }
      if (sub == '/media/copy' && method == 'POST') {
        if (caller != DialCaller.author) {
          return const DialResponse(403, {'error': 'author only'});
        }
        return await _mediaCopy(body);
      }
      if (sub == '/media/assets' && method == 'GET') {
        if (caller != DialCaller.author) {
          return const DialResponse(403, {'error': 'author only'});
        }
        return await _mediaAssets();
      }
      // The Ship channel (slice 5): automation up to the button. Author
      // only — guests never see pipeline state.
      if (sub.startsWith('/ship/')) {
        if (caller != DialCaller.author) {
          return const DialResponse(403, {'error': 'author only'});
        }
        final s = ship;
        if (s == null) {
          return const DialResponse(
              503, {'error': 'ship off — artifact is not inside a git repo'});
        }
        if (method == 'GET' && sub == '/ship/status') {
          return DialResponse(200, await s.status());
        }
        if (method == 'POST' && sub == '/ship/pr') {
          return await _shipPr(body, s);
        }
        if (method == 'POST' && sub == '/ship/merge') {
          return await _shipVerb(s.merge);
        }
        if (method == 'POST' && sub == '/ship/close') {
          return await _shipVerb(s.close);
        }
        if (method == 'POST' && sub == '/ship/sync') {
          return await _shipVerb(s.sync);
        }
        if (method == 'GET' && sub == '/ship/deploy/ready') {
          final dir = artifactDir;
          if (dir == null) {
            return const DialResponse(503, {'error': 'no artifact dir'});
          }
          return DialResponse(
              200, {'blockers': await s.deployBlockers(dir)});
        }
        if (method == 'POST' && sub == '/ship/deploy') {
          final dir = artifactDir;
          if (dir == null) {
            return const DialResponse(503, {'error': 'no artifact dir'});
          }
          return await _shipVerb(() => s.deploy(
              artifactDir: dir, statusFn: () async => await s.status()));
        }
      }
      // The selection handoff (slice 7): author registers, anyone with the
      // pointer id reads — the id is capability enough for the GET.
      if (method == 'POST' && sub == '/selection') {
        if (caller != DialCaller.author) {
          return const DialResponse(403, {'error': 'author only'});
        }
        return _registerSelection(body);
      }
      if (method == 'GET' && sub.startsWith('/selection/')) {
        return _readSelection(sub.substring('/selection/'.length));
      }
      // Compose request (2026-08-26): the floating card's Arxa tab asks
      // the studio panel to insert the pointer line + snapshot into the
      // composer. Validates the selection server-side (TTL honored) and
      // answers a THIN pointer — label/route for the pointer line, but
      // never the PNG: images stay out of the event log (operator
      // decision 2026-08-25, fetch-on-arrival).
      if (method == 'POST' && sub == '/compose') {
        if (caller != DialCaller.author) {
          return const DialResponse(403, {'error': 'author only'});
        }
        return _composeSelection(body);
      }
      // Compose ack: the panel (a trusted cross-origin caller) confirms
      // the insert LANDED, so the card can show a verified ✓ instead of
      // a hopeful one. Relayed to everyone; the island matches by id.
      if (method == 'POST' && sub == '/compose-ack') {
        final m = _map(body, '/compose-ack');
        final id = m['id'] is String ? _str(m, 'id', 40) : null;
        if (id == null) {
          return const DialResponse(400, {'error': 'id is required'});
        }
        return DialResponse(200, {'id': id, 'ack': true});
      }
      return DialResponse(404, {'error': 'no such dial route: $sub'});
    } on FormatException catch (e) {
      return DialResponse(400, {'error': e.message});
    }
  }

  // ── the Draft Overlay (Design Mode; decisions 5/11) ────────────────────

  DialResponse _noDraftStore() => const DialResponse(
      503, {'error': 'draft overlay is not configured on this server'});

  /// Preview-commit parity (2026-08-24): an el: patch whose authored name=
  /// anchor does not resolve to exactly ONE source site previews fine but
  /// is refused at commit - surface that as a warning so the dock can
  /// badge it before the edit hardens. Machine-id patches are stamped by
  /// the stamper and cannot collide, so they never warn.
  List<Map<String, dynamic>>? _parityWarnings(DraftOverlay d) {
    final base = artifactDir;
    if (base == null) return null; // no source tree to scan - stay quiet
    final warnings = <Map<String, dynamic>>[];
    for (final e in d.patches.entries) {
      final el = elKeyOf(e.key);
      if (el == null) continue;
      final sites = nameSiteLocations(Directory(base), el).length;
      if (sites != 1) {
        warnings.add({
          'el': el,
          'sites': sites,
          'problem': sites == 0 ? 'missing' : 'ambiguous',
        });
      }
    }
    return warnings.isEmpty ? null : warnings;
  }

  Future<DialResponse> _getDraft() async {
    final ds = draftStore;
    if (ds == null) return _noDraftStore();
    final d = await ds.load();
    if (d == null) return const DialResponse(200, {'draft': null});
    final warn = _parityWarnings(d);
    return DialResponse(200, {
      'draft': d.toJson(),
      if (warn != null) 'warnings': warn,
    });
  }

  Future<DialResponse> _putDraft(Object? body) async {
    final ds = draftStore;
    if (ds == null) return _noDraftStore();
    final d = DraftOverlay.fromJson(body, artifact: artifact);
    await ds.save(d);
    final warn = _parityWarnings(d);
    return DialResponse(200, {
      'ok': true,
      'patches': d.patches.length,
      'tokens': d.tokens.length,
      'updatedAt': d.updatedAt,
      if (warn != null) 'warnings': warn,
    });
  }

  Future<DialResponse> _clearDraft() async {
    final ds = draftStore;
    if (ds == null) return _noDraftStore();
    await ds.clear();
    return const DialResponse(200, {'ok': true});
  }

  /// The studio-socket commit (decision 2): hand the studio agent the draft
  /// as structured patch ops. The agent applies them to artifact source with
  /// `appbox design patch` (tokens go to the token sheet's :root), re-runs
  /// lint/gates, and clears the draft on success. Non-destructive by design:
  /// only the agent's DELETE says the commit landed.
  Future<DialResponse> _commitDraft() async {
    final ds = draftStore;
    if (ds == null) return _noDraftStore();
    final d = await ds.load();
    if (d == null || d.isEmpty) {
      return const DialResponse(
          400, {'error': 'draft is empty — nothing to commit'});
    }
    final ops = [
      for (final e in d.patches.entries)
        if (!e.value.isEmpty)
          // el:-prefixed keys (authored identity wins on divergence) become
          // --el ops; everything else rides the machine id.
          elKeyOf(e.key) != null
              ? {'el': elKeyOf(e.key), ...e.value.toJson()}
              : {'id': e.key, ...e.value.toJson()},
    ];
    return DialResponse(200, {
      'ok': true,
      'artifact': artifact,
      'artifactDir': artifactDir,
      'tokens': d.tokens,
      'ops': ops,
      'note': 'apply each op with appbox design patch (id ops: positional '
          'data-arxa-id; el ops: --el <data-el>; edits: --style/--set/--text; '
          'seed-backed text ops also carry --was/--nth/--page/--locale from '
          'the op json; --locale writes only that locale SSOT slice) '
          'and the tokens to the token sheet; on success '
          'DELETE /__dial/draft',
    });
  }

  Future<DialResponse> _mediaSearch(Object? body) async {
    final m = _map(body, '/media/search');
    final proxy = media;
    if (proxy == null || !proxy.enabled) {
      return const DialResponse(503, {
        'error': 'media proxy off — set UNSPLASH_ACCESS_KEY / PEXELS_API_KEY '
            'in the design server environment'
      });
    }
    if (m['q'] is! String || (m['q'] as String).trim().isEmpty) {
      return const DialResponse(400, {'error': 'q is required'});
    }
    final q = _str(m, 'q', DialMediaProxy.maxQuery);
    final kind = m['kind'] == 'video' ? 'video' : 'photo';
    final hits = await proxy.search(q, kind);
    return DialResponse(200, {
      'results': [for (final h in hits) h.toJson()],
    });
  }

  Future<DialResponse> _mediaCopy(Object? body) async {
    final m = _map(body, '/media/copy');
    final proxy = media;
    if (proxy == null || !proxy.enabled) {
      return const DialResponse(503, {'error': 'media proxy off'});
    }
    final dir = artifactDir;
    if (dir == null) {
      return const DialResponse(503, {'error': 'no artifact dir'});
    }
    if (m['url'] is! String || m['name'] is! String) {
      return const DialResponse(400,
          {'error': 'url and name are required'});
    }
    final url = _str(m, 'url', 2048);
    final name = _str(m, 'name', 120);
    final credit = m['credit'] is String ? _str(m, 'credit', 120) : 'unknown';
    final provider =
        m['provider'] is String ? _str(m, 'provider', 24) : 'unsplash';
    try {
      final path = await proxy.copyInto(
        url: url,
        nameHint: name,
        credit: credit,
        provider: provider,
        artifactDir: dir,
      );
      return DialResponse(201, {'path': path});
    } on MediaRefusal catch (e) {
      return DialResponse(400, {'error': e.message});
    }
  }

  Future<DialResponse> _mediaAssets() async {
    final proxy = media;
    if (proxy == null) {
      return const DialResponse(503, {'error': 'media proxy off'});
    }
    final dir = artifactDir;
    if (dir == null) {
      return const DialResponse(503, {'error': 'no artifact dir'});
    }
    return DialResponse(200, {'assets': proxy.listAssets(dir)});
  }

  Future<DialResponse> _shipPr(Object? body, DialShip s) async {
    final m = _map(body, '/ship/pr');
    if (m['title'] is! String || (m['title'] as String).trim().isEmpty) {
      return const DialResponse(400, {'error': 'title is required'});
    }
    final dir = artifactDir;
    if (dir == null) {
      return const DialResponse(503, {'error': 'no artifact dir'});
    }
    final title = _str(m, 'title', 120);
    final bodyText = m['body'] is String ? _str(m, 'body', 8000) : '';
    try {
      final r = await s.commitAndPr(
          artifactDir: dir, title: title, body: bodyText);
      return DialResponse(201, r);
    } on ShipRefusal catch (ex) {
      return DialResponse(409, {'error': ex.message});
    }
  }

  Future<DialResponse> _shipVerb(
      Future<Map<String, dynamic>> Function() verb) async {
    try {
      return DialResponse(200, await verb());
    } on ShipRefusal catch (ex) {
      return DialResponse(409, {'error': ex.message});
    }
  }

  static const _selectionTtl = Duration(minutes: 20);
  static const _selectionCap = 20;

  Future<DialResponse> _registerSelection(Object? body) async {
    final m = _map(body, '/selection');
    final key = m['key'] is String ? _str(m, 'key', 200) : null;
    final label = m['label'] is String ? _str(m, 'label', 120) : null;
    if (key == null || label == null) {
      return const DialResponse(400, {'error': 'key and label are required'});
    }
    final text = m['text'] is String ? (m['text'] as String) : null;
    if (text != null && text.length > 600) {
      return const DialResponse(400, {'error': 'text over 600 chars'});
    }
    final png = m['png'] is String ? (m['png'] as String) : null;
    if (png != null &&
        (!png.startsWith('data:image/') || png.length > 400_000)) {
      return const DialResponse(400,
          {'error': 'png must be a data URL under 400 KB'});
    }
    final styles = m['styles'] is Map
        ? Map<String, dynamic>.from(m['styles'] as Map)
        : <String, dynamic>{};
    final id = 's${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '${(label.hashCode & 0xffff).toRadixString(36)}';
    final entry = <String, dynamic>{
      'id': id,
      'key': key,
      'label': label,
      'kind': m['kind'] is String ? _str(m, 'kind', 40) : 'element',
      'group': m['group'] is String ? _str(m, 'group', 40) : 'generic',
      'route': m['route'] is String ? _str(m, 'route', 200) : '/',
      'artifact': artifact,
      if (text != null) 'text': text,
      if (png != null) 'png': png,
      if (styles.isNotEmpty) 'styles': styles,
      'law':
          'The design structure is LOCKED. Edit ONLY this element via the '
          'appbox design patch contract (data-arxa-id / data-el identity); '
          'never add or remove elements, never change widget kinds.',
      'fetch': '/__dial/selection/$id',
    };
    // TTL sweep then cap.
    final now = DateTime.now();
    _selections.removeWhere((_, v) => now.difference(v.$1) > _selectionTtl);
    while (_selections.length >= _selectionCap) {
      _selections.remove(_selections.keys.first);
    }
    _selections[id] = (now, entry);
    return DialResponse(201, {'id': id, 'fetch': entry['fetch']});
  }

  Future<DialResponse> _composeSelection(Object? body) async {
    final m = _map(body, '/compose');
    final id = m['id'] is String ? _str(m, 'id', 40) : null;
    if (id == null) {
      return const DialResponse(400, {'error': 'id is required'});
    }
    if (!RegExp(r'^s[0-9a-z]{3,20}$').hasMatch(id)) {
      return const DialResponse(400, {'error': 'bad selection id'});
    }
    final hit = _selections[id];
    if (hit == null || DateTime.now().difference(hit.$1) > _selectionTtl) {
      _selections.remove(id);
      return const DialResponse(
          404, {'error': 'selection expired — send again from the card'});
    }
    final e = hit.$2;
    return DialResponse(200, {
      'id': id,
      'fetch': e['fetch'],
      'label': e['label'],
      'route': e['route'],
    });
  }

  Future<DialResponse> _readSelection(String id) async {
    if (!RegExp(r'^s[0-9a-z]{3,20}$').hasMatch(id)) {
      return const DialResponse(400, {'error': 'bad selection id'});
    }
    final hit = _selections[id];
    if (hit == null || DateTime.now().difference(hit.$1) > _selectionTtl) {
      _selections.remove(id);
      return const DialResponse(
          404, {'error': 'selection expired — ask again from the card'});
    }
    return DialResponse(200, hit.$2);
  }

  Future<DialResponse> _listPins() async {
    final pins = await store.listPins(artifact);
    return DialResponse(200, {
      'store': store.kind,
      'pins': [for (final p in pins) p.toJson()],
    });
  }

  Future<DialResponse> _createPin(Object? body, DialCaller caller) async {
    final m = _map(body);
    final route = _str(m, 'route', _Caps.route);
    final viewport = _map(m['viewport'], 'viewport');
    final w = _dim(viewport['w']);
    final h = _dim(viewport['h']);
    final anchor =
        m['anchor'] == null ? <String, dynamic>{} : _map(m['anchor'], 'anchor');
    final el = anchor['el'] == null ? null : _str(anchor, 'el', _Caps.el);
    // The anchor's text snapshot (research slice 2026-08-25): optional,
    // empty means absent (an ancient island sending text:'' must not 400),
    // over-cap is rejected like every other string here.
    final anchorText = anchor['text'];
    final contextText = anchorText is String && anchorText.trim().isNotEmpty
        ? _str(anchor, 'text', _Caps.context)
        : null;
    final rect = _rect(_map(anchor['rect'], 'anchor.rect'));
    final drawing = asDrawing(m['drawing']);
    final text = _str(m, 'body', _Caps.body);
    final name = m['name'] == null
        ? (caller == DialCaller.author ? 'author' : 'guest')
        : _str(m, 'name', _Caps.name);
    final now = DateTime.now().toUtc().toIso8601String();
    final pin = DialPin(
      id: dialNewId(),
      artifact: artifact,
      route: route,
      viewportW: w,
      viewportH: h,
      anchorEl: el,
      rect: rect,
      contextText: contextText,
      drawing: drawing,
      status: DialPinStatus.open,
      authorKind: caller,
      authorName: name,
      body: text,
      createdAt: now,
      updatedAt: now,
    );
    await store.createPin(pin);
    return DialResponse(201, {'pin': pin.toJson()});
  }

  Future<DialResponse> _setStatus(Object? body) async {
    final m = _map(body);
    final id = _str(m, 'id', 64);
    final status = DialPinStatus.parse(m['status'] as String?);
    if (status == null) {
      throw const FormatException(
          'status must be one of open|triaged|in_progress|resolved|wont_do');
    }
    final pin = await store.setStatus(id, status);
    if (pin == null) return const DialResponse(404, {'error': 'no such pin'});
    return DialResponse(200, {'pin': pin.toJson()});
  }

  Future<DialResponse> _reply(Object? body, DialCaller caller) async {
    final m = _map(body);
    final id = _str(m, 'id', 64);
    final text = _str(m, 'body', _Caps.body);
    final name = m['name'] == null
        ? (caller == DialCaller.author ? 'author' : 'guest')
        : _str(m, 'name', _Caps.name);
    final reply = await store.addReply(id, caller, name, text);
    if (reply == null) return const DialResponse(404, {'error': 'no such pin'});
    return DialResponse(201, {'reply': reply.toJson()});
  }

  Future<DialResponse> _share(Object? body) async {
    final m = body == null ? <String, dynamic>{} : _map(body);
    final days = m['days'] is int ? m['days'] as int : 30;
    if (days < 1 || days > 365) {
      throw const FormatException('days must be 1..365');
    }
    final token = await store.mintShareLink(artifact, Duration(days: days));
    return DialResponse(201, {
      'token': token,
      // The island composes the full URL (local origin now; the stable
      // Workers hostname once the Publish slice lands).
      'query': '?dial=$token',
    });
  }

  // ── validation primitives: every failure is a FormatException → 400 ──

  static Map<String, dynamic> _map(Object? v, [String what = 'body']) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, x) => MapEntry('$k', x));
    throw FormatException('$what must be a JSON object');
  }

  static String _str(Map<String, dynamic> m, String key, int cap) {
    final v = m[key];
    if (v is! String || v.isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    if (v.length > cap) throw FormatException('$key exceeds $cap chars');
    return v;
  }

  static int _dim(Object? v) {
    final n = v is int ? v : int.tryParse('$v');
    if (n == null || n < 1 || n > 10000) {
      throw const FormatException('viewport dims must be 1..10000');
    }
    return n;
  }

  static Map<String, double> _rect(Map<String, dynamic> m) {
    double num_(String k) {
      final v = m[k];
      final d = v is num ? v.toDouble() : double.tryParse('$v');
      if (d == null || !d.isFinite) {
        throw FormatException('rect.$k must be a finite number');
      }
      return d;
    }

    return {'x': num_('x'), 'y': num_('y'), 'w': num_('w'), 'h': num_('h')};
  }
}
