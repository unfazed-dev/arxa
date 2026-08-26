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
///     ARXA_SUPABASE_URL + ARXA_SUPABASE_SERVICE_KEY. The service key
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

import 'design_axes.dart';
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
    this.guestId,
    this.guestEmail,
  });

  final String id;
  final DialCaller authorKind;
  final String authorName;
  final String body;
  final String createdAt;
  String? guestId;
  String? guestEmail;

  Map<String, dynamic> toJson() => {
        'id': id,
        'author': authorKind.name,
        if (guestEmail != null) 'guestEmail': guestEmail,
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
    this.guestId,
    this.guestEmail,
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

  /// Arc 2 attribution: set by construction when the pin arrived on a
  /// personal link (guest_id relation + the queryable email copy the PII
  /// scrub erases). Null on author pins and anonymous-link pins. Mutable:
  /// the PII scrub de-relates and scrubs in place.
  String? guestId;
  String? guestEmail;

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
        if (guestEmail != null) 'guestEmail': guestEmail,
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
/// expiring, comment-level permission only. Arc 2 (2026-08-26): a link minted
/// through /guests is PERSONAL — it carries the registered guest whose link
/// it is, so every pin and reply that arrives on it is attributed by
/// construction. Legacy anonymous links resolve with all three guest fields
/// null and keep working until they expire.
class ShareLinkGrant {
  const ShareLinkGrant({
    required this.artifact,
    required this.expiresAt,
    this.guestId,
    this.guestEmail,
    this.guestName,
  });

  final String artifact;

  /// ISO-8601; null never expires (operator choice, not the default).
  final String? expiresAt;

  /// The registered guest this personal link belongs to; null = anonymous.
  final String? guestId;
  final String? guestEmail;
  final String? guestName;

  bool get expired {
    if (expiresAt == null) return false;
    final at = DateTime.tryParse(expiresAt!);
    return at == null || DateTime.now().toUtc().isAfter(at);
  }
}

/// A registered reviewer of one design (arc 2): the author registers the
/// guest BEFORE the link is sent, keyed by email. unique(design, email) —
/// the same person reviewing two designs is two rows, so closing one
/// engagement deletes exactly that engagement's PII.
class DialGuest {
  DialGuest({
    required this.id,
    required this.email,
    required this.displayName,
    required this.createdAt,
    required this.linksAlive,
  });

  final String id;
  final String email;
  final String displayName;
  final String createdAt;

  /// Unexpired personal links this guest holds.
  final int linksAlive;

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': displayName,
        'createdAt': createdAt,
        'linksAlive': linksAlive,
      };
}

/// What minting a personal link returns: the raw token (shown once, stored
/// hashed) and the guest row it now belongs to.
class GuestLink {
  const GuestLink({required this.token, required this.guest});
  final String token;
  final DialGuest guest;
}

/// The email law for guest registration: trimmed, lowercased, one @, a dot
/// in the domain, ≤254 (RFC max). Throws FormatException — the API answers
/// 400 through the same path as every other validation.
String dialGuestEmail(Object? v) {
  if (v is! String) throw const FormatException('email must be a string');
  final email = v.trim().toLowerCase();
  if (email.isEmpty ||
      email.length > 254 ||
      !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
    throw const FormatException('email must be a valid address');
  }
  return email;
}

/// The friendly label a guest's pins carry: the display name when the author
/// gave one, else the email's local part — never the full email, which lives
/// only in the attribution columns the PII scrub can erase.
String dialGuestLabel(String? name, String email) {
  final n = name?.trim() ?? '';
  if (n.isNotEmpty) return n;
  final at = email.indexOf('@');
  return at <= 0 ? email : email.substring(0, at);
}

// ── store seam ───────────────────────────────────────────────────────────

abstract class DialStore {
  /// 'supabase' or 'memory' — the island badges the memory mode 'local'.
  String get kind;

  Future<List<DialPin>> listPins(String artifact, {String? route});
  Future<DialPin> createPin(DialPin pin);

  /// Returns null when the id is unknown.
  Future<DialPin?> setStatus(String id, DialPinStatus status);
  /// [guestId]/[guestEmail] carry arc 2 attribution when the reply arrived
  /// on a personal link; both null for the author and anonymous links.
  Future<DialReply?> addReply(String pinId, DialCaller kind, String name,
      String body,
      {String? guestId, String? guestEmail});

  /// Mints a Share Link: returns the RAW token (shown once, stored hashed).
  Future<String> mintShareLink(String artifact, Duration ttl);
  Future<ShareLinkGrant?> resolveShareLink(String token);

  // ── the identity plane (arc 2, 2026-08-26) ─────────────────────────────
  // Personal bearer links replace anonymous tokens for client review: the
  // author registers the guest's email at mint, the link carries the guest,
  // and attribution on pins/replies is by construction. May throw on a
  // store failure — the API answers 502 honestly.

  Future<GuestLink> mintGuestLink(
      String artifact, Duration ttl, String email, String? displayName);
  Future<List<DialGuest>> listGuests(String artifact);

  /// The PII path: deletes the guest (their links cascade), keeps their
  /// feedback (guest_id set-null), and scrubs the email copy off it.
  /// Returns the deleted guest, or null when no such email is registered.
  Future<DialGuest?> deleteGuest(String artifact, String email);
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

  /// (artifact, email) → guest. The memory identity plane: session-scoped,
  /// like every other memory row — the island's 'local' badge covers it.
  final _guests = <String, DialGuest>{};

  String _guestKey(String artifact, String email) => '$artifact|$email';

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
  Future<DialReply?> addReply(String pinId, DialCaller kind, String name,
      String body,
      {String? guestId,
      String? guestEmail}) async {
    final pin = _pins[pinId];
    if (pin == null) return null;
    final reply = DialReply(
      id: dialNewId(),
      authorKind: kind,
      authorName: name,
      body: body,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      guestId: guestId,
      guestEmail: guestEmail,
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

  @override
  Future<GuestLink> mintGuestLink(
      String artifact, Duration ttl, String email, String? displayName) async {
    final key = _guestKey(artifact, email);
    final existing = _guests[key];
    // Latest mint wins the display name (the same law as the Supabase
    // upsert: the newest registration refreshes the row); identity, email,
    // and created_at never move.
    final guest = existing != null
        ? DialGuest(
            id: existing.id,
            email: existing.email,
            displayName: displayName?.trim() ?? '',
            createdAt: existing.createdAt,
            linksAlive: existing.linksAlive,
          )
        : DialGuest(
            id: dialNewId(),
            email: email,
            displayName: displayName?.trim() ?? '',
            createdAt: DateTime.now().toUtc().toIso8601String(),
            linksAlive: 0,
          );
    final raw = _mintToken();
    _links[_hashToken(raw)] = ShareLinkGrant(
      artifact: artifact,
      expiresAt: DateTime.now().toUtc().add(ttl).toIso8601String(),
      guestId: guest.id,
      guestEmail: guest.email,
      guestName: guest.displayName,
    );
    final counted = _links.values.where((g) =>
        g.guestId == guest.id && !g.expired).length;
    _guests[key] = DialGuest(
      id: guest.id,
      email: guest.email,
      displayName: guest.displayName,
      createdAt: guest.createdAt,
      linksAlive: counted,
    );
    return GuestLink(token: raw, guest: _guests[key]!);
  }

  @override
  Future<List<DialGuest>> listGuests(String artifact) async {
    final prefix = _guestKey(artifact, '');
    final out = [
      for (final e in _guests.entries)
        if (e.key.startsWith(prefix)) _withLiveCount(e.value)
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  DialGuest _withLiveCount(DialGuest g) {
    final alive =
        _links.values.where((l) => l.guestId == g.id && !l.expired).length;
    if (alive == g.linksAlive) return g;
    return DialGuest(
      id: g.id,
      email: g.email,
      displayName: g.displayName,
      createdAt: g.createdAt,
      linksAlive: alive,
    );
  }

  @override
  Future<DialGuest?> deleteGuest(String artifact, String email) async {
    final key = _guestKey(artifact, email);
    final guest = _guests.remove(key);
    if (guest == null) return null;
    // Their links die with them (the SQL path rides on delete cascade);
    // their feedback survives, de-related and email-scrubbed.
    _links.removeWhere((_, l) => l.guestId == guest.id);
    for (final pin in _pins.values) {
      if (pin.guestId == guest.id) {
        pin.guestEmail = null;
        pin.guestId = null;
      }
      for (final reply in pin.replies) {
        if (reply.guestId == guest.id) {
          reply.guestEmail = null;
          reply.guestId = null;
        }
      }
    }
    return guest;
  }
}

/// PostgREST against the operator-owned central project. Table shapes are
/// the migration in supabase/migrations/20260823_design_dial.sql — keep them
/// in lockstep. One HttpClient per store; no pooling beyond dart:io's own.
class SupabaseDialStore implements DialStore {
  SupabaseDialStore({
    required this.url,
    required this.serviceKey,
    this.project,
    this.author,
  });

  final String url;
  final String serviceKey;

  /// Arc 2 identity plane: the pipeline project from the artifact's
  /// arxa.json marker + the author from ~/.arxa/identity.json. When
  /// either is absent the store degrades to basename keys (legacy rows) and
  /// mintGuestLink answers 503 through the API — guest registration is a
  /// registered-design capability, never a guess.
  final String? project;

  /// Kept for parity with SupabaseAxesStore.fromConfig; the dial store does
  /// not write author fields itself (the axes store's registration owns
  /// them), it only reads the design row.
  final AuthorIdentity? author;

  String? _designId;

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
  ///   1. ARXA_SUPABASE_URL + ARXA_SUPABASE_SERVICE_KEY in the process env
  ///   2. the machine-scoped file ~/.arxa/supabase — key=value lines
  ///      (url= / service_key=), '#' comments, same convention as
  ///      ~/.arxa/trusted-origins: an operator fact about THIS machine,
  ///      never repo state, never the artifact's config.
  static SupabaseDialStore? fromConfig(
      {Map<String, String>? env,
      String? credentialsFileText,
      String? project,
      String? artifact,
      AuthorIdentity? author}) {
    final e = env ?? Platform.environment;
    var url = e['ARXA_SUPABASE_URL'];
    var key = e['ARXA_SUPABASE_SERVICE_KEY'];
    if ((url == null || url.isEmpty || key == null || key.isEmpty) &&
        credentialsFileText != null) {
      final file = parseSupabaseCredentials(credentialsFileText);
      url ??= file.url;
      key ??= file.key;
    }
    if (url == null || url.isEmpty || key == null || key.isEmpty) return null;
    return SupabaseDialStore(
        url: url, serviceKey: key, project: project, author: author)
      .._boundArtifact = artifact;
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

  Map<String, dynamic> _pinRow(DialPin p) => {
        'id': p.id,
        'artifact': p.artifact,
        if (p.guestId != null) 'guest_id': p.guestId,
        if (p.guestEmail != null) 'guest_email': p.guestEmail,
        if (_designId != null) 'design_id': _designId,
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
        guestId: r['guest_id'] as String?,
        guestEmail: r['guest_email'] as String?,
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
        guestId: rr['guest_id'] as String?,
        guestEmail: rr['guest_email'] as String?,
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
  Future<DialReply?> addReply(String pinId, DialCaller kind, String name,
      String body,
      {String? guestId,
      String? guestEmail}) async {
    final reply = DialReply(
      id: dialNewId(),
      authorKind: kind,
      authorName: name,
      body: body,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      guestId: guestId,
      guestEmail: guestEmail,
    );
    final res = await _req('POST', 'design_dial_replies',
        body: {
          'id': reply.id,
          'pin_id': pinId,
          'author_kind': kind.name,
          'author_name': name,
          'body': body,
          'created_at': reply.createdAt,
          'guest_id': ?guestId,
          'guest_email': ?guestEmail,
          if (_designId != null) 'design_id': _designId,
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
            '&select=artifact,expires_at,guest_id,'
            'design_dial_guests(email,display_name)');
    final rows = jsonDecode(await res.transform(utf8.decoder).join()) as List;
    if (rows.isEmpty) return null;
    final row = rows.first as Map<String, dynamic>;
    final guest = row['design_dial_guests'];
    final guestMap = guest is Map ? guest as Map<String, dynamic> : null;
    final grant = ShareLinkGrant(
      artifact: row['artifact'] as String,
      expiresAt: row['expires_at'] as String?,
      guestId: row['guest_id'] as String?,
      guestEmail: guestMap?['email'] as String?,
      guestName: guestMap?['display_name'] as String?,
    );
    return grant.expired ? null : grant;
  }

  // ── the identity plane (arc 2) ──────────────────────────────────────────

  /// The design's registered id — same upsert the axes store performs (the
  /// axes registration owns the row; both converge on merge-duplicates).
  /// Throws when no marker named a project: guest identity is a
  /// registered-design capability, never a guessed key.
  Future<String> _ensureDesignId() async {
    final known = _designId;
    if (known != null) return known;
    final p = project;
    if (p == null || p.isEmpty) {
      throw StateError('guest registration needs an arxa.json project');
    }
    // INSERT, and on the natural-key conflict read the row back. This
    // PostgREST does NOT infer the (project, artifact) unique constraint
    // for upsert conflict resolution - measured live 2026-08-26:
    // merge-duplicates AND ignore-duplicates both answer 23505 on an
    // existing row, so the upsert is a plain 409 here. The fallback GET
    // is deterministic (the row provably exists - that is why we got
    // the 409); the only race is two first-boots inserting at once, and
    // the loser lands in the GET.
    final response = await _req('POST', 'design_dial_designs', body: {
      'project': p,
      'artifact': _artifactName,
      if (author != null) 'author_email': author!.email,
      if (author != null) 'author_name': author!.name,
    }, extraHeaders: {
      'Prefer': 'return=representation'
    });
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode == 409) {
      final get = await _req(
          'GET',
          'design_dial_designs?project=eq.${Uri.encodeComponent(p)}'
              '&artifact=eq.${Uri.encodeComponent(_artifactName)}'
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

  /// The artifact this store serves, bound at construction (fromConfig) or
  /// on first use (bind) — the name the designs table registers under.
  String get _artifactName => _boundArtifact ?? '';

  String? _boundArtifact;

  /// Binds the artifact identity used for design registration. The dial API
  /// knows its artifact; the store learns it once at boot.
  void bind(String artifact) => _boundArtifact ??= artifact;

  static DialGuest _guestFromRow(Map<String, dynamic> r, int linksAlive) =>
      DialGuest(
        id: r['id'] as String,
        email: r['email'] as String,
        displayName: (r['display_name'] as String?) ?? '',
        createdAt: (r['created_at'] as String?) ?? '',
        linksAlive: linksAlive,
      );

  @override
  Future<GuestLink> mintGuestLink(
      String artifact, Duration ttl, String email, String? displayName) async {
    bind(artifact);
    final designId = await _ensureDesignId();
    final name = displayName?.trim() ?? '';
    // Upsert on (design_id, email): re-minting for the same person converges
    // on their existing row instead of forking identity.
    final res = await _req('POST', 'design_dial_guests', body: {
      'id': dialNewId(),
      'design_id': designId,
      'email': email,
      'display_name': name,
    }, extraHeaders: {
      'Prefer': 'resolution=merge-duplicates,return=representation'
    });
    final text = await utf8.decoder.bind(res).join();
    if (res.statusCode >= 300) {
      throw StateError('guest registration failed (${res.statusCode}): $text');
    }
    final rows = jsonDecode(text);
    if (rows is! List || rows.isEmpty || rows.first is! Map) {
      throw StateError('guest registration returned no row: $text');
    }
    final guestRow = rows.first as Map<String, dynamic>;
    final guest = _guestFromRow(guestRow, 1);
    final raw = _mintToken();
    await _req('POST', 'design_dial_share_links',
        body: {
          'token_hash': _hashToken(raw),
          'artifact': artifact,
          'expires_at': DateTime.now().toUtc().add(ttl).toIso8601String(),
          'guest_id': guest.id,
          'design_id': designId,
        },
        extraHeaders: {'Prefer': 'return=minimal'});
    return GuestLink(token: raw, guest: guest);
  }

  @override
  Future<List<DialGuest>> listGuests(String artifact) async {
    bind(artifact);
    final designId = await _ensureDesignId();
    final res = await _req('GET',
        'design_dial_guests?design_id=eq.$designId&select=*,'
        'design_dial_share_links(token_hash,expires_at)&order=created_at.asc');
    final text = await utf8.decoder.bind(res).join();
    if (res.statusCode >= 300) {
      throw StateError('guest list failed (${res.statusCode}): $text');
    }
    final rows = jsonDecode(text);
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map<String, dynamic>)
          _guestFromRow(
              row,
              _liveLinks(row['design_dial_share_links'])),
    ];
  }

  static int _liveLinks(Object? v) {
    if (v is! List) return 0;
    final now = DateTime.now().toUtc();
    var alive = 0;
    for (final link in v) {
      if (link is! Map) continue;
      final exp = link['expires_at'] as String?;
      if (exp == null) {
        alive++;
        continue;
      }
      final at = DateTime.tryParse(exp);
      if (at == null || now.isAfter(at) == false) alive++;
    }
    return alive;
  }

  @override
  Future<DialGuest?> deleteGuest(String artifact, String email) async {
    bind(artifact);
    final designId = await _ensureDesignId();
    final find = await _req('GET',
        'design_dial_guests?design_id=eq.$designId&email=eq.${Uri.encodeComponent(email)}'
            '&select=*');
    final findText = await utf8.decoder.bind(find).join();
    if (find.statusCode >= 300) {
      throw StateError('guest lookup failed (${find.statusCode}): $findText');
    }
    final found = jsonDecode(findText);
    if (found is! List || found.isEmpty || found.first is! Map) return null;
    final guest = _guestFromRow(found.first as Map<String, dynamic>, 0);
    // The PII path, in order: scrub the email copy off surviving feedback,
    // then delete the row (links cascade, pins/replies keep guest_id=null).
    await _req('PATCH', 'design_dial_pins?guest_id=eq.${guest.id}',
        body: {'guest_email': null},
        extraHeaders: {'Prefer': 'return=minimal'});
    await _req('PATCH', 'design_dial_replies?guest_id=eq.${guest.id}',
        body: {'guest_email': null},
        extraHeaders: {'Prefer': 'return=minimal'});
    _invalidatePins();
    await _req('DELETE',
        'design_dial_guests?id=eq.${guest.id}',
        extraHeaders: {'Prefer': 'return=minimal'});
    return guest;
  }
}

/// The ~/.arxa/supabase file, parsed. A line that is not key=value is
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
      this.ship,
      this.axes});

  final DialStore store;

  /// The artifact identity pins and links scope to (artifact dir basename).
  final String artifact;

  /// The Draft Overlay's file store (decisions 5/11: local-server state,
  /// never Supabase). Null disables the draft/commit routes (503).
  final DraftFileStore? draftStore;

  /// The artifact's absolute dir — reported by /commit so the studio agent
  /// knows where to run `arxa design patch`.
  final String? artifactDir;

  /// The media proxy (slice 4, 2026-08-24): server-side Unsplash/Pexels
  /// search + copy-into-artifact. Null disables the routes (503).
  final DialMediaProxy? media;

  /// The Ship channel (slice 5, 2026-08-24): confined git+gh. Author-only;
  /// null (not a git repo) disables the routes (503).
  final DialShip? ship;

  /// The axes plane (arc 1, 2026-08-25): the published style/theme pick.
  /// Author-only writes; guests preview via ?style/?theme URL overrides
  /// and never reach this store. Null (no marker / kind not app / dial
  /// off) disables the route (503).
  final AxesStore? axes;

  /// Selection handoff registry (slice 7, 2026-08-24): the card's "Ask
  /// arxa" registers an organized selection context here; the studio agent
  /// fetches it by pointer id. Bounded: capped, TTL'd, author-only writes.
  final Map<String, (DateTime, Map<String, dynamic>)> _selections = {};

  /// POST /__dial/axes — publish {style, theme}. Both required and both
  /// axis-lawful: the island always sends the full pair it rendered, so a
  /// flip can never half-apply.
  Future<DialResponse> _setAxes(Object? body) async {
    final store = axes;
    if (store == null) {
      return const DialResponse(503, {'error': 'axes unavailable'});
    }
    // _map throws FormatException on a non-object body — the handle's
    // catch answers the 400 for every route uniformly.
    final pick = AxesPick.fromJson(_map(body, '/axes'));
    if (pick == null) {
      return const DialResponse(400, {
        'error': 'style and theme required (lowercase a-z0-9-, max 40)'
      });
    }
    try {
      await store.save(pick);
    } catch (error) {
      return DialResponse(502, {'error': 'axes store write failed: $error'});
    }
    return DialResponse(200, {'ok': true, 'axes': pick.toJson()});
  }

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
        return await _createPin(body, caller, grant);
      }
      if (method == 'POST' && sub == '/pins/status') {
        if (caller != DialCaller.author) {
          return const DialResponse(403, {'error': 'author only'});
        }
        return await _setStatus(body);
      }
      if (method == 'POST' && sub == '/pins/reply') {
        return await _reply(body, caller, grant);
      }
      if (method == 'POST' && sub == '/share') {
        if (caller != DialCaller.author) {
          return const DialResponse(403, {'error': 'author only'});
        }
        return await _share(body);
      }
      // The identity plane (arc 2, 2026-08-26): register the guest, mint
      // their PERSONAL bearer link, roster the reviewers, revoke + scrub.
      // Author-only — who may review the design is the author's call alone.
      if (sub == '/guests' && method == 'GET') {
        if (caller != DialCaller.author) {
          return const DialResponse(403, {'error': 'author only'});
        }
        return await _listGuests();
      }
      if (sub == '/guests' && method == 'POST') {
        if (caller != DialCaller.author) {
          return const DialResponse(403, {'error': 'author only'});
        }
        return await _mintGuest(body);
      }
      if (sub == '/guests/revoke' && method == 'POST') {
        if (caller != DialCaller.author) {
          return const DialResponse(403, {'error': 'author only'});
        }
        return await _revokeGuest(body);
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
      // The axes plane (arc 1, 2026-08-25): publish the style/theme pick.
      // Author-only — a guest's flip rides the URL override, never the
      // store; the serve seam applies both identically.
      if (method == 'POST' && sub == '/axes') {
        if (caller != DialCaller.author) {
          return const DialResponse(403, {'error': 'author only'});
        }
        return await _setAxes(body);
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
      // inserted:false (studio had no open composer) is echoed so the
      // card tells THAT truth instead of faking the ✓ (2026-08-26).
      if (method == 'POST' && sub == '/compose-ack') {
        final m = _map(body, '/compose-ack');
        final id = m['id'] is String ? _str(m, 'id', 40) : null;
        if (id == null) {
          return const DialResponse(400, {'error': 'id is required'});
        }
        return DialResponse(200, {
          'id': id,
          'ack': true,
          if (m['inserted'] is bool) 'inserted': m['inserted'],
        });
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
      'warnings': ?warn,
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
      'warnings': ?warn,
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
  /// `arxa design patch` (tokens go to the token sheet's :root), re-runs
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
      'note': 'apply each op with arxa design patch (id ops: positional '
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
      'text': ?text,
      'png': ?png,
      if (styles.isNotEmpty) 'styles': styles,
      'law':
          'The design structure is LOCKED. Edit ONLY this element via the '
          'arxa design patch contract (data-arxa-id / data-el identity); '
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
    // Protocol marker echo (2026-08-26): the tabbed card sends v:2 so a
    // v2-aware panel can tell its store-only Send apart from a stale
    // pre-tabs island's ask (which WAS the whole flow). The response IS
    // the broadcast frame, so the marker must ride it — and ONLY when
    // the caller sent it, or every legacy island would look v2.
    return DialResponse(201, {
      'id': id,
      'fetch': entry['fetch'],
      if (m['v'] == 2) 'v': 2,
    });
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

  Future<DialResponse> _createPin(
      Object? body, DialCaller caller, ShareLinkGrant? grant) async {
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
    // Attribution (arc 2): a personal link answers WHO the guest is — the
    // author_name carries only the friendly label, the email lives in the
    // attribution column. A body name from a bearer guest is ignored: the
    // registry is the truth, never a typed string.
    final bearerEmail = grant?.guestEmail;
    final bearerId = grant?.guestId;
    final name = bearerEmail != null
        ? dialGuestLabel(grant?.guestName, bearerEmail)
        : (m['name'] == null
            ? (caller == DialCaller.author ? 'author' : 'guest')
            : _str(m, 'name', _Caps.name));
    final now = DateTime.now().toUtc().toIso8601String();
    final pin = DialPin(
      id: dialNewId(),
      artifact: artifact,
      guestId: bearerId,
      guestEmail: bearerEmail,
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

  Future<DialResponse> _reply(
      Object? body, DialCaller caller, ShareLinkGrant? grant) async {
    final m = _map(body);
    final id = _str(m, 'id', 64);
    final text = _str(m, 'body', _Caps.body);
    final bearerEmail = grant?.guestEmail;
    final name = bearerEmail != null
        ? dialGuestLabel(grant?.guestName, bearerEmail)
        : (m['name'] == null
            ? (caller == DialCaller.author ? 'author' : 'guest')
            : _str(m, 'name', _Caps.name));
    final reply = await store.addReply(id, caller, name, text,
        guestId: grant?.guestId, guestEmail: bearerEmail);
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

  Future<DialResponse> _listGuests() async {
    try {
      final guests = await store.listGuests(artifact);
      return DialResponse(200, {
        'store': store.kind,
        'guests': [for (final g in guests) g.toJson()],
      });
    } on StateError catch (e) {
      return DialResponse(503, {'error': e.message});
    } catch (error) {
      return DialResponse(502, {'error': 'guest list failed: $error'});
    }
  }

  Future<DialResponse> _mintGuest(Object? body) async {
    final m = _map(body, '/guests');
    final email = dialGuestEmail(m['email']);
    final name = m['name'] is String ? _str(m, 'name', 80) : null;
    final days = m['days'] is int ? m['days'] as int : 30;
    if (days < 1 || days > 365) {
      throw const FormatException('days must be 1..365');
    }
    try {
      final link = await store.mintGuestLink(
          artifact, Duration(days: days), email, name);
      return DialResponse(201, {
        'token': link.token,
        'query': '?dial=${link.token}',
        'email': link.guest.email,
        'name': link.guest.displayName,
      });
    } on StateError catch (e) {
      return DialResponse(503, {'error': e.message});
    } catch (error) {
      return DialResponse(502, {'error': 'guest link mint failed: $error'});
    }
  }

  Future<DialResponse> _revokeGuest(Object? body) async {
    final m = _map(body, '/guests/revoke');
    final email = dialGuestEmail(m['email']);
    try {
      final gone = await store.deleteGuest(artifact, email);
      if (gone == null) {
        return DialResponse(
            404, {'error': 'no such guest on this design'});
      }
      return DialResponse(200, {
        'ok': true,
        'revoked': gone.email,
        // The PII contract, said out loud so the UI never has to guess.
        'scrubbed': 'links deleted; feedback kept, de-attributed',
      });
    } on StateError catch (e) {
      return DialResponse(503, {'error': e.message});
    } catch (error) {
      return DialResponse(502, {'error': 'guest revoke failed: $error'});
    }
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
