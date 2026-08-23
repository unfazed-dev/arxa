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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;

// ── vocabulary ───────────────────────────────────────────────────────────

/// The pin kanban (locked decision 9): the closed status set, wire names.
enum DialPinStatus {
  open('open'),
  triaged('triaged'),
  inProgress('in_progress'),
  resolved('resolved'),
  wontDo('wont_do');

  const DialPinStatus(this.wire);
  final String wire;

  static DialPinStatus? parse(String? s) {
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
        'anchor': {'el': anchorEl, 'rect': rect},
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
  final HttpClient _http = HttpClient();

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
    final req = await _http.openUrl(method, Uri.parse('$url/rest/v1/$path'));
    req.headers.set('apikey', serviceKey);
    req.headers.set('Authorization', 'Bearer $serviceKey');
    extraHeaders?.forEach(req.headers.set);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    return req.close();
  }

  static Map<String, dynamic> _pinRow(DialPin p) => {
        'id': p.id,
        'artifact': p.artifact,
        'route': p.route,
        'viewport_w': p.viewportW,
        'viewport_h': p.viewportH,
        'anchor_el': p.anchorEl,
        'rect': p.rect,
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

  @override
  Future<List<DialPin>> listPins(String artifact, {String? route}) async {
    var q = 'design_dial_pins?artifact=eq.${Uri.encodeComponent(artifact)}'
        '&order=created_at.asc'
        '&select=*,design_dial_replies(*),design_dial_drawings(strokes)';
    if (route != null) q += '&route=eq.${Uri.encodeComponent(route)}';
    final res = await _req('GET', q);
    final rows = jsonDecode(await res.transform(utf8.decoder).join()) as List;
    return [
      for (final r in rows)
        _pinFromRow(r as Map<String, dynamic>, [
          for (final rr
              in (r['design_dial_replies'] as List? ?? const []))
            _replyFromRow(rr as Map<String, dynamic>),
        ]),
    ];
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
}

/// The /__dial/* API as a pure function: no HttpRequest, no IO — the server
/// adapter (design_server.dart) reads the body and passes it here.
class DialApi {
  DialApi({required this.store, required this.artifact});

  final DialStore store;

  /// The artifact identity pins and links scope to (artifact dir basename).
  final String artifact;

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
      return DialResponse(404, {'error': 'no such dial route: $sub'});
    } on FormatException catch (e) {
      return DialResponse(400, {'error': e.message});
    }
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
