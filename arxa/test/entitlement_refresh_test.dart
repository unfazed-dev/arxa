// Auto-refresh slice: the pure refresh-window decision (`refreshNeed`),
// Supabase session persistence (`Session`), and the `ensureFreshEntitlement`
// orchestrator against a loopback HTTP server standing in for Supabase auth
// + the /activate Edge Function (mocked HTTP — no network).
//
// Signing uses the DEV fixture keypair through the same test seam as
// entitlement_test.dart (debugPublicKeyOverride); tokens are bound to the
// REAL machine fingerprint because ensureFreshEntitlement fails closed on
// wrong-machine tokens.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/entitlement.dart';
import 'package:arxa/entitlement_refresh.dart';
import 'package:test/test.dart';

import 'entitlement_fixture.dart';

int _epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

final _now = DateTime.utc(2027, 1, 15, 12);
final _fpr = Entitlement.machineFingerprint()!;

String _tokenExpiring(DateTime exp) => makeEntitlementJwt(
    devEntitlementKey,
    entitlementClaims(
      fpr: _fpr,
      nbf: _epoch(_now.subtract(const Duration(days: 1))),
      exp: _epoch(exp),
      feat: const ['emit.scaffold'],
    ));

EntitlementVerdict _verdict(EntitlementStatus status, {DateTime? exp}) =>
    EntitlementVerdict(status: status, reason: 'test', expires: exp);

void main() {
  setUpAll(
      () => Entitlement.debugPublicKeyOverride = devEntitlementKey.publicKey);
  tearDownAll(() => Entitlement.debugPublicKeyOverride = null);

  group('refreshNeed (pure decision)', () {
    test('valid token expiring well past the window: none', () {
      final v = _verdict(EntitlementStatus.valid,
          exp: _now.add(const Duration(days: 7)));
      expect(refreshNeed(v, _now), RefreshNeed.none);
    });

    test('valid token expiring within 48h: opportunistic', () {
      final v = _verdict(EntitlementStatus.valid,
          exp: _now.add(const Duration(hours: 24)));
      expect(refreshNeed(v, _now), RefreshNeed.opportunistic);
    });

    test('valid token expiring exactly at the window edge: opportunistic', () {
      final v = _verdict(EntitlementStatus.valid,
          exp: _now.add(const Duration(hours: 48)));
      expect(refreshNeed(v, _now), RefreshNeed.opportunistic);
    });

    test('grace (already past exp, coasting offline): opportunistic', () {
      final v = _verdict(EntitlementStatus.grace,
          exp: _now.subtract(const Duration(days: 2)));
      expect(refreshNeed(v, _now), RefreshNeed.opportunistic);
    });

    test('expired past grace: required', () {
      final v = _verdict(EntitlementStatus.expired,
          exp: _now.subtract(const Duration(days: 60)));
      expect(refreshNeed(v, _now), RefreshNeed.required);
    });

    test('invalid: required', () {
      expect(
          refreshNeed(_verdict(EntitlementStatus.invalid), _now),
          RefreshNeed.required);
    });

    test('missing token: required', () {
      expect(refreshNeed(_verdict(EntitlementStatus.none), _now),
          RefreshNeed.required);
    });

    test('custom window is honored', () {
      final v = _verdict(EntitlementStatus.valid,
          exp: _now.add(const Duration(hours: 24)));
      expect(refreshNeed(v, _now, window: const Duration(hours: 12)),
          RefreshNeed.none);
    });
  });

  group('Session persistence', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('arxa_session_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('save/load round-trip, mode 600, no token in the clear name', () {
      final path = '${tmp.path}/nested/session.json';
      Session(
        accessToken: 'at-1',
        refreshToken: 'rt-1',
        expiresAt: DateTime.utc(2027, 2),
      ).save(path);
      final loaded = Session.load(path)!;
      expect(loaded.accessToken, 'at-1');
      expect(loaded.refreshToken, 'rt-1');
      expect(loaded.expiresAt, DateTime.utc(2027, 2));
      if (!Platform.isWindows) {
        final args =
            Platform.isMacOS ? ['-f', '%Lp', path] : ['-c', '%a', path];
        final mode = Process.runSync('stat', args).stdout.toString().trim();
        expect(mode, '600');
      }
    });

    test('missing file: null', () {
      expect(Session.load('${tmp.path}/absent.json'), isNull);
    });

    test('corrupt json: null, never throws', () {
      final path = '${tmp.path}/session.json';
      File(path).writeAsStringSync('not json {');
      expect(Session.load(path), isNull);
    });

    test('json missing tokens: null', () {
      final path = '${tmp.path}/session.json';
      File(path).writeAsStringSync(jsonEncode({'access_token': ''}));
      expect(Session.load(path), isNull);
    });

    test('fromAuthResponse prefers expires_at, falls back to expires_in', () {
      final at = _epoch(DateTime.utc(2027, 3));
      final a = Session.fromAuthResponse(
          {'access_token': 'a', 'refresh_token': 'r', 'expires_at': at}, _now);
      expect(a.expiresAt, DateTime.utc(2027, 3));
      final b = Session.fromAuthResponse(
          {'access_token': 'a', 'refresh_token': 'r', 'expires_in': 3600},
          _now);
      expect(b.expiresAt, _now.add(const Duration(hours: 1)));
      expect(
          () => Session.fromAuthResponse({'access_token': 'a'}, _now),
          throwsA(isA<EntitlementRefreshFailure>()));
    });

    test('isStale: null expiry is stale; future expiry is not', () {
      expect(
          Session(accessToken: 'a', refreshToken: 'r').isStale(_now), isTrue);
      expect(
          Session(
                  accessToken: 'a',
                  refreshToken: 'r',
                  expiresAt: _now.add(const Duration(hours: 1)))
              .isStale(_now),
          isFalse);
      expect(
          Session(
                  accessToken: 'a',
                  refreshToken: 'r',
                  expiresAt: _now.add(const Duration(seconds: 30)))
              .isStale(_now),
          isTrue,
          reason: 'inside the 60s skew');
    });
  });

  group('ensureFreshEntitlement (loopback Supabase)', () {
    late Directory tmp;
    late String tokenPath;
    late String sessionPath;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('arxa_refresh_');
      tokenPath = '${tmp.path}/entitlement.jwt';
      sessionPath = '${tmp.path}/session.json';
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    void putSession({DateTime? expiresAt}) => Session(
          accessToken: 'access-ok',
          refreshToken: 'refresh-ok',
          expiresAt: expiresAt ?? _now.add(const Duration(hours: 1)),
        ).save(sessionPath);

    /// Loopback stand-in for Supabase. [acceptAccess] is the bearer token
    /// /activate accepts (anything else → 401). Records requests in [log].
    Future<(HttpServer, SupabaseConfig, List<String>)> startServer(
        {String acceptAccess = 'access-ok'}) async {
      final log = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final body = jsonDecode(await utf8.decoder.bind(req).join());
        Map<String, Object?> out;
        var code = 200;
        if (req.uri.path == '/auth/v1/token' &&
            req.uri.queryParameters['grant_type'] == 'refresh_token') {
          log.add('refresh:${body['refresh_token']}');
          out = {
            'access_token': 'access-fresh',
            'refresh_token': 'refresh-rotated',
            'expires_in': 3600,
          };
        } else if (req.uri.path == '/auth/v1/token' &&
            req.uri.queryParameters['grant_type'] == 'password') {
          log.add('password:${body['email']}');
          out = {
            'access_token': acceptAccess,
            'refresh_token': 'refresh-ok',
            'expires_in': 3600,
          };
        } else if (req.uri.path == '/functions/v1/activate') {
          final auth = req.headers.value('authorization') ?? '';
          log.add('activate:$auth');
          if (auth != 'Bearer $acceptAccess') {
            code = 401;
            out = {'error': 'invalid or expired auth token'};
          } else {
            out = {
              'token':
                  _tokenExpiring(_now.add(const Duration(days: 7)))
            };
          }
        } else {
          code = 404;
          out = {'error': 'not found'};
        }
        req.response.statusCode = code;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(out));
        await req.response.close();
      });
      final cfg = SupabaseConfig(
          url: 'http://127.0.0.1:${server.port}', anonKey: 'anon-test');
      return (server, cfg, log);
    }

    test('fresh token: no-op, zero network traffic', () async {
      File(tokenPath).writeAsStringSync(
          _tokenExpiring(_now.add(const Duration(days: 6))));
      putSession();
      final (server, cfg, log) = await startServer();
      try {
        final out = await ensureFreshEntitlement(
            config: cfg, tokenPath: tokenPath, sessionPath: sessionPath,
            now: _now);
        expect(out.refreshed, isFalse);
        expect(out.fatal, isFalse);
        expect(log, isEmpty);
      } finally {
        await server.close(force: true);
      }
    });

    test('near-expiry token + fresh session: activates and overwrites cache',
        () async {
      File(tokenPath).writeAsStringSync(
          _tokenExpiring(_now.add(const Duration(hours: 12))));
      putSession();
      final (server, cfg, log) = await startServer();
      try {
        final out = await ensureFreshEntitlement(
            config: cfg, tokenPath: tokenPath, sessionPath: sessionPath,
            now: _now);
        expect(out.refreshed, isTrue);
        expect(out.fatal, isFalse);
        expect(log, ['activate:Bearer access-ok']);
        final v = Entitlement.verifyFile(tokenPath, now: _now,
            fingerprint: _fpr);
        expect(v.status, EntitlementStatus.valid);
        expect(v.expires, _now.add(const Duration(days: 7)));
      } finally {
        await server.close(force: true);
      }
    });

    test('stale session: refresh grant first, session file rotated', () async {
      putSession(expiresAt: _now.subtract(const Duration(minutes: 5)));
      final (server, cfg, log) =
          await startServer(acceptAccess: 'access-fresh');
      try {
        final out = await ensureFreshEntitlement(
            config: cfg, tokenPath: tokenPath, sessionPath: sessionPath,
            now: _now);
        expect(out.refreshed, isTrue);
        expect(log,
            ['refresh:refresh-ok', 'activate:Bearer access-fresh']);
        expect(Session.load(sessionPath)!.refreshToken, 'refresh-rotated');
      } finally {
        await server.close(force: true);
      }
    });

    test('401 from activate: one session refresh, then retry succeeds',
        () async {
      // Session claims to be fresh but the server only accepts the refreshed
      // access token — forces the 401 → refresh → retry path.
      putSession();
      final (server, cfg, log) =
          await startServer(acceptAccess: 'access-fresh');
      try {
        final out = await ensureFreshEntitlement(
            config: cfg, tokenPath: tokenPath, sessionPath: sessionPath,
            now: _now);
        expect(out.refreshed, isTrue);
        expect(log, [
          'activate:Bearer access-ok',
          'refresh:refresh-ok',
          'activate:Bearer access-fresh',
        ]);
      } finally {
        await server.close(force: true);
      }
    });

    test('backend unreachable + token still valid: non-fatal', () async {
      File(tokenPath).writeAsStringSync(
          _tokenExpiring(_now.add(const Duration(hours: 12))));
      putSession();
      // Bind-then-close guarantees a dead port.
      final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close(force: true);
      final out = await ensureFreshEntitlement(
          config:
              SupabaseConfig(url: 'http://127.0.0.1:$port', anonKey: 'anon'),
          tokenPath: tokenPath,
          sessionPath: sessionPath,
          now: _now);
      expect(out.refreshed, isFalse);
      expect(out.fatal, isFalse, reason: 'offline tolerance');
      // The still-valid cache must be untouched.
      expect(Entitlement.verifyFile(tokenPath, now: _now, fingerprint: _fpr)
          .unlocks, isTrue);
    });

    test('no token + no session: fatal with the login hint', () async {
      final out = await ensureFreshEntitlement(
          config: const SupabaseConfig(url: 'http://127.0.0.1:1', anonKey: 'a'),
          tokenPath: tokenPath,
          sessionPath: sessionPath,
          now: _now);
      expect(out.refreshed, isFalse);
      expect(out.fatal, isTrue);
      expect(out.message, contains('arxa login'));
    });

    test('no token + session + backend unreachable: fatal with hint',
        () async {
      putSession();
      final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close(force: true);
      final out = await ensureFreshEntitlement(
          config:
              SupabaseConfig(url: 'http://127.0.0.1:$port', anonKey: 'anon'),
          tokenPath: tokenPath,
          sessionPath: sessionPath,
          now: _now);
      expect(out.fatal, isTrue);
      expect(out.message, contains('arxa login'));
    });

    test('wrong-machine token from activate is never cached', () async {
      final stale = _tokenExpiring(_now.add(const Duration(hours: 12)));
      File(tokenPath).writeAsStringSync(stale);
      putSession();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'token': makeEntitlementJwt(
              devEntitlementKey,
              entitlementClaims(
                fpr: 'f' * 64, // some other machine
                nbf: _epoch(_now.subtract(const Duration(days: 1))),
                exp: _epoch(_now.add(const Duration(days: 7))),
                feat: const ['emit.scaffold'],
              ))
        }));
        await req.response.close();
      });
      try {
        final out = await ensureFreshEntitlement(
            config: SupabaseConfig(
                url: 'http://127.0.0.1:${server.port}', anonKey: 'anon'),
            tokenPath: tokenPath,
            sessionPath: sessionPath,
            now: _now);
        expect(out.refreshed, isFalse);
        expect(out.fatal, isFalse, reason: 'old token still unlocks');
        expect(File(tokenPath).readAsStringSync(), stale,
            reason: 'cache must be untouched');
      } finally {
        await server.close(force: true);
      }
    });

    test('supabasePasswordLogin returns a persistable session', () async {
      final (server, cfg, log) = await startServer();
      try {
        final s = await supabasePasswordLogin(cfg, 'u@example.com', 'pw',
            now: _now);
        s.save(sessionPath);
        expect(log, ['password:u@example.com']);
        expect(Session.load(sessionPath)!.accessToken, 'access-ok');
      } finally {
        await server.close(force: true);
      }
    });

    test('SupabaseConfig.fromEnvironment: overrides win, defaults otherwise',
        () {
      final overridden = SupabaseConfig.fromEnvironment({
        'ARXA_SUPABASE_URL': 'https://byo.example.com/',
        'ARXA_SUPABASE_ANON_KEY': 'byo-key',
      });
      expect(overridden.url, 'https://byo.example.com');
      expect(overridden.anonKey, 'byo-key');
      final defaults = SupabaseConfig.fromEnvironment({});
      expect(defaults.url, SupabaseConfig.officialUrl);
      expect(defaults.anonKey, SupabaseConfig.officialAnonKey);
    });
  });
}
