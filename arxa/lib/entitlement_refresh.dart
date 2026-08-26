/// Entitlement auto-refresh — keeps the cached entitlement JWT
/// (`~/.arxa/entitlement.jwt`, 7-day TTL) renewed for ANY user, with no
/// hardcoded accounts and no dev bypasses.
///
/// Tokens are minted exclusively by the `/activate` Edge Function
/// (docs/plans/entitlement-backend-runbook.md). This module supplies the
/// client half:
///
///   * `arxa login` (`loginMain`) — email+password against Supabase auth,
///     persisting the SESSION (access+refresh token) at `~/.arxa/session.json`
///     mode 600. The entitlement itself is then activated immediately.
///   * `ensureFreshEntitlement` — the orchestrator: when the cached token
///     expires within [defaultRefreshWindow] (or is missing/invalid), refresh
///     the Supabase session if stale (refresh_token grant), call `/activate`
///     with this machine's fingerprint, and overwrite the cache — but ONLY
///     after the returned token verifies for this machine.
///   * `maybeRefreshEntitlement` — the silent pre-command hook wired before
///     the entitlement-gated dispatches in bin/arxa.dart. Never fatal, never
///     noisy: offline tolerance means a failure while the current token still
///     unlocks is a non-event, and sessionless (free-tier) users see nothing.
///     The fail-closed `entitlementAssertion` at the paywall remains the only
///     fatal point.
///   * `refreshNeed` — the pure decision function (unit-tested): does this
///     verdict call for no refresh, an opportunistic one (failure non-fatal),
///     or a required one (only then may the caller degrade to unentitled)?
///
/// Backend endpoints default to the official arxa Supabase project but are
/// overridable via `ARXA_SUPABASE_URL` / `ARXA_SUPABASE_ANON_KEY` so
/// self-hosted/BYO backends work. The anon key is a public client credential
/// by design — embedding it is not a secret leak.
///
/// This module NEVER prints tokens or passwords.
library;

import 'dart:convert';
import 'dart:io';

import 'entitlement.dart';

/// How close to `exp` the cached token may get before we renew it.
const defaultRefreshWindow = Duration(hours: 48);

/// Supabase backend coordinates. Defaults are the official arxa backend;
/// env overrides make self-hosted backends first-class.
class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.anonKey});

  /// Base project URL, no trailing slash (e.g. `https://xyz.supabase.co`).
  final String url;

  /// The project's anon (publishable) key — public by design.
  final String anonKey;

  static const officialUrl = 'https://nqvzhxcldntyayilykfy.supabase.co';
  static const officialAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6'
      'Im5xdnpoeGNsZG50eWF5aWx5a2Z5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc0NzQwMD'
      'ksImV4cCI6MjEwMzA1MDAwOX0.n9Ywgm84IKvTCc0VaF825TAv6hYMD8G6F4xmz3MVh-0';

  /// Resolve from [env] (default [Platform.environment]):
  /// `ARXA_SUPABASE_URL` / `ARXA_SUPABASE_ANON_KEY`, else official defaults.
  factory SupabaseConfig.fromEnvironment([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    String pick(String key, String fallback) {
      final v = e[key]?.trim();
      return (v == null || v.isEmpty) ? fallback : v;
    }

    var url = pick('ARXA_SUPABASE_URL', officialUrl);
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return SupabaseConfig(
        url: url, anonKey: pick('ARXA_SUPABASE_ANON_KEY', officialAnonKey));
  }
}

/// A persisted Supabase auth session. Stored at `~/.arxa/session.json`
/// mode 600 — same posture as the entitlement cache. Tokens never printed.
class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;

  /// When [accessToken] expires (UTC). Null when the server omitted it —
  /// treated as already stale so we refresh before use.
  final DateTime? expiresAt;

  /// Default store location: `~/.arxa/session.json` (per-user, like the
  /// entitlement cache). Null when no home directory exists.
  static String? defaultPath() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    return home == null ? null : '$home/.arxa/session.json';
  }

  /// Whether [accessToken] should be refreshed before use at [now].
  bool isStale(DateTime now, {Duration skew = const Duration(seconds: 60)}) =>
      expiresAt == null || !expiresAt!.isAfter(now.add(skew));

  /// Parse a Supabase auth token-endpoint response body. Throws
  /// [EntitlementRefreshFailure] when the tokens are absent.
  factory Session.fromAuthResponse(Map<String, Object?> body, DateTime now) {
    final access = body['access_token'];
    final refresh = body['refresh_token'];
    if (access is! String || access.isEmpty ||
        refresh is! String || refresh.isEmpty) {
      throw const EntitlementRefreshFailure(
          'auth response carried no session tokens');
    }
    DateTime? expiresAt;
    final expAt = body['expires_at'];
    final expIn = body['expires_in'];
    if (expAt is num) {
      expiresAt =
          DateTime.fromMillisecondsSinceEpoch(expAt.toInt() * 1000, isUtc: true);
    } else if (expIn is num) {
      expiresAt = now.add(Duration(seconds: expIn.toInt()));
    }
    return Session(
        accessToken: access, refreshToken: refresh, expiresAt: expiresAt);
  }

  /// Load from [path]. Null on missing, unreadable, or malformed file —
  /// never throws (a broken session file just means "not logged in").
  static Session? load(String path) {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      final decoded = jsonDecode(f.readAsStringSync());
      if (decoded is! Map) return null;
      final access = decoded['access_token'];
      final refresh = decoded['refresh_token'];
      if (access is! String || access.isEmpty ||
          refresh is! String || refresh.isEmpty) {
        return null;
      }
      final expAt = decoded['expires_at'];
      return Session(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: expAt is num
            ? DateTime.fromMillisecondsSinceEpoch(expAt.toInt() * 1000,
                isUtc: true)
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Persist to [path] mode 600, creating parent directories.
  void save(String path) {
    writeSecretFile(
        path,
        jsonEncode({
          'access_token': accessToken,
          'refresh_token': refreshToken,
          if (expiresAt != null)
            'expires_at': expiresAt!.millisecondsSinceEpoch ~/ 1000,
        }));
  }
}

/// Write [content] to [path] with owner-only permissions (mode 600 on POSIX),
/// creating parent directories. Shared by the session store and the
/// entitlement cache writer.
void writeSecretFile(String path, String content) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(content);
  if (!Platform.isWindows) {
    Process.runSync('chmod', ['600', path]);
  }
}

/// What the current verdict calls for.
enum RefreshNeed {
  /// Token unlocks and expiry is comfortably out — do nothing.
  none,

  /// Token still unlocks but expires within the window (or is coasting on
  /// offline grace) — refresh, and swallow failures (offline tolerance).
  opportunistic,

  /// Token does not unlock (missing/invalid/expired past grace) — refresh,
  /// and only if THIS fails may the caller degrade to unentitled.
  required,
}

/// Pure decision: given the offline [verdict] at [now], is a refresh needed?
RefreshNeed refreshNeed(EntitlementVerdict verdict, DateTime now,
    {Duration window = defaultRefreshWindow}) {
  if (!verdict.unlocks) return RefreshNeed.required;
  if (verdict.status == EntitlementStatus.grace) return RefreshNeed.opportunistic;
  final exp = verdict.expires;
  // A verified `valid` token always carries exp; treat a missing one as fine
  // rather than hammering the backend.
  if (exp == null) return RefreshNeed.none;
  return exp.isAfter(now.add(window))
      ? RefreshNeed.none
      : RefreshNeed.opportunistic;
}

/// A refresh-path failure with an honest, secret-free message.
class EntitlementRefreshFailure implements Exception {
  const EntitlementRefreshFailure(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// Outcome of [ensureFreshEntitlement].
class RefreshOutcome {
  const RefreshOutcome(
      {required this.refreshed, required this.fatal, required this.message});

  /// A new token was minted and cached.
  final bool refreshed;

  /// The machine is left unentitled (refresh was required AND failed).
  /// While the cached token still unlocks, failures are never fatal.
  final bool fatal;

  /// Honest, secret-free description of what happened.
  final String message;
}

const _loginHint = 'run `arxa login` to (re)activate this machine';

/// The orchestrator. See the library docs for semantics. [config],
/// [tokenPath], [sessionPath] and [now] are injectable for tests; production
/// callers pass nothing.
Future<RefreshOutcome> ensureFreshEntitlement({
  SupabaseConfig? config,
  String? tokenPath,
  String? sessionPath,
  DateTime? now,
  Duration window = defaultRefreshWindow,
}) async {
  final at = now ?? DateTime.now().toUtc();
  final verdict = Entitlement.verifyCurrent(path: tokenPath, now: at);
  final need = refreshNeed(verdict, at, window: window);
  if (need == RefreshNeed.none) {
    return RefreshOutcome(
        refreshed: false,
        fatal: false,
        message: 'entitlement fresh — expires '
            '${verdict.expires?.toIso8601String() ?? 'unknown'}');
  }
  final fatalIfFails = need == RefreshNeed.required;

  RefreshOutcome fail(String what) => RefreshOutcome(
        refreshed: false,
        fatal: fatalIfFails,
        message: fatalIfFails
            ? '$what — $_loginHint'
            : '$what — current entitlement still valid, continuing offline',
      );

  final resolvedSessionPath = sessionPath ?? Session.defaultPath();
  if (resolvedSessionPath == null) {
    return fail('no home directory — nowhere to store a Supabase session');
  }
  var session = Session.load(resolvedSessionPath);
  if (session == null) return fail('no Supabase session');

  final cfg = config ?? SupabaseConfig.fromEnvironment();
  final resolvedTokenPath = tokenPath ?? Entitlement.defaultPath();
  if (resolvedTokenPath == null) {
    return fail('no home directory — nowhere to cache an entitlement');
  }

  try {
    if (session.isStale(at)) {
      session = await refreshSupabaseSession(cfg, session, now: at);
      session.save(resolvedSessionPath);
    }
    String token;
    try {
      token = await activateEntitlement(cfg, session.accessToken);
    } on EntitlementRefreshFailure catch (e) {
      if (e.statusCode != 401) rethrow;
      // Access token rejected despite looking fresh — refresh once and retry.
      session = await refreshSupabaseSession(cfg, session, now: at);
      session.save(resolvedSessionPath);
      token = await activateEntitlement(cfg, session.accessToken);
    }
    // Never overwrite the cache with a token that does not verify for THIS
    // machine — a bad write would destroy a working offline-grace token.
    final minted = Entitlement.verify(token,
        now: at, fingerprint: Entitlement.machineFingerprint());
    if (!minted.unlocks) {
      return fail('activate returned a token that does not verify '
          '(${minted.reason})');
    }
    writeSecretFile(resolvedTokenPath, token);
    return RefreshOutcome(
        refreshed: true,
        fatal: false,
        message: 'entitlement refreshed — expires '
            '${minted.expires?.toIso8601String() ?? 'unknown'}');
  } on EntitlementRefreshFailure catch (e) {
    return fail(e.message);
  } catch (e) {
    // Network unreachable, TLS failure, timeout, … — honest but secret-free.
    return fail('entitlement refresh failed (${e.runtimeType})');
  }
}

/// Silent best-effort hook run before entitlement-gated commands. Never
/// throws, never prints: the paywall assertion is the single fatal voice.
/// Sessionless (free-tier) users return immediately with zero network I/O.
Future<void> maybeRefreshEntitlement() async {
  try {
    final sessionPath = Session.defaultPath();
    if (sessionPath == null || Session.load(sessionPath) == null) return;
    await ensureFreshEntitlement();
  } catch (_) {
    // Deliberately silent — offline tolerance.
  }
}

// ---------------------------------------------------------------------------
// Supabase HTTP calls (dart:io only — the package has no http dependency).
// ---------------------------------------------------------------------------

/// Email+password sign-in: `POST /auth/v1/token?grant_type=password`.
Future<Session> supabasePasswordLogin(
    SupabaseConfig cfg, String email, String password,
    {DateTime? now}) async {
  final at = now ?? DateTime.now().toUtc();
  final (code, body) = await _postJson(
    Uri.parse('${cfg.url}/auth/v1/token?grant_type=password'),
    headers: {'apikey': cfg.anonKey},
    body: {'email': email, 'password': password},
  );
  if (code != 200) {
    throw EntitlementRefreshFailure(_authError('login failed', code, body),
        statusCode: code);
  }
  return Session.fromAuthResponse(body, at);
}

/// Session renewal: `POST /auth/v1/token?grant_type=refresh_token`.
Future<Session> refreshSupabaseSession(SupabaseConfig cfg, Session session,
    {DateTime? now}) async {
  final at = now ?? DateTime.now().toUtc();
  final (code, body) = await _postJson(
    Uri.parse('${cfg.url}/auth/v1/token?grant_type=refresh_token'),
    headers: {'apikey': cfg.anonKey},
    body: {'refresh_token': session.refreshToken},
  );
  if (code != 200) {
    throw EntitlementRefreshFailure(
        _authError('session refresh failed', code, body),
        statusCode: code);
  }
  return Session.fromAuthResponse(body, at);
}

/// Mint a fresh entitlement for THIS machine via the `/activate` Edge
/// Function. Returns the compact JWS; the caller verifies before caching.
Future<String> activateEntitlement(
    SupabaseConfig cfg, String accessToken) async {
  final fpr = Entitlement.machineFingerprint();
  if (fpr == null) {
    throw const EntitlementRefreshFailure(
        'machine fingerprint undeterminable');
  }
  final platform = Platform.isMacOS
      ? 'macos'
      : Platform.isWindows
          ? 'windows'
          : 'linux';
  final (code, body) = await _postJson(
    Uri.parse('${cfg.url}/functions/v1/activate'),
    headers: {
      'apikey': cfg.anonKey,
      'authorization': 'Bearer $accessToken',
    },
    body: {'fpr': fpr, 'platform': platform},
  );
  if (code != 200) {
    throw EntitlementRefreshFailure(_authError('activate failed', code, body),
        statusCode: code);
  }
  final token = body['token'];
  if (token is! String || token.isEmpty) {
    throw const EntitlementRefreshFailure('activate returned no token');
  }
  return token;
}

String _authError(String what, int code, Map<String, Object?> body) {
  final detail = body['error_description'] ?? body['error'] ?? body['msg'];
  return detail is String && detail.isNotEmpty
      ? '$what (HTTP $code): $detail'
      : '$what (HTTP $code)';
}

Future<(int, Map<String, Object?>)> _postJson(
  Uri uri, {
  required Map<String, String> headers,
  required Object body,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.postUrl(uri).timeout(timeout);
    req.headers.contentType = ContentType.json;
    headers.forEach(req.headers.set);
    req.write(jsonEncode(body));
    final res = await req.close().timeout(timeout);
    final text = await utf8.decoder.bind(res).join().timeout(timeout);
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      decoded = null;
    }
    return (
      res.statusCode,
      decoded is Map ? decoded.cast<String, Object?>() : <String, Object?>{},
    );
  } finally {
    client.close(force: true);
  }
}

// ---------------------------------------------------------------------------
// `arxa login`
// ---------------------------------------------------------------------------

/// Entry point for `arxa login [--email <email>]`. Prompts for whatever is
/// missing (password always prompted, echo off on a tty; read as a plain
/// line when piped). Persists the session, then activates immediately.
/// Exit 0 only when both the login and the activation succeed.
Future<int> loginMain(
  List<String> args, {
  SupabaseConfig? config,
  String? sessionPath,
  String? tokenPath,
}) async {
  String? email;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--email' && i + 1 < args.length) {
      email = args[++i];
    } else {
      stderr.writeln('usage: arxa login [--email <email>]');
      return 64;
    }
  }
  email ??= _promptLine('email: ');
  if (email == null || email.trim().isEmpty) {
    stderr.writeln('arxa login: an email is required');
    return 64;
  }
  final password = _promptSecret('password: ');
  if (password == null || password.isEmpty) {
    stderr.writeln('arxa login: a password is required');
    return 64;
  }

  final resolvedSessionPath = sessionPath ?? Session.defaultPath();
  if (resolvedSessionPath == null) {
    stderr.writeln('arxa login: no home directory — nowhere to store the '
        'session');
    return 1;
  }
  final cfg = config ?? SupabaseConfig.fromEnvironment();
  final Session session;
  try {
    session = await supabasePasswordLogin(cfg, email.trim(), password);
  } on EntitlementRefreshFailure catch (e) {
    stderr.writeln('arxa login: ${e.message}');
    return 1;
  } catch (e) {
    stderr.writeln('arxa login: could not reach ${cfg.url} '
        '(${e.runtimeType})');
    return 1;
  }
  session.save(resolvedSessionPath);
  stdout.writeln('logged in — session saved to $resolvedSessionPath');

  final outcome = await ensureFreshEntitlement(
    config: cfg,
    sessionPath: resolvedSessionPath,
    tokenPath: tokenPath,
  );
  stdout.writeln(outcome.message);
  return outcome.fatal ? 1 : 0;
}

String? _promptLine(String label) {
  stdout.write(label);
  return stdin.readLineSync();
}

String? _promptSecret(String label) {
  stdout.write(label);
  if (!stdin.hasTerminal) return stdin.readLineSync();
  final prevEcho = stdin.echoMode;
  stdin.echoMode = false;
  try {
    final line = stdin.readLineSync();
    stdout.writeln();
    return line;
  } finally {
    stdin.echoMode = prevEcho;
  }
}
