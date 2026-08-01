// Tier-1 verification tests — port of tier1.py's scenario coverage.
//
// Three layers:
//   - SeedAuthBackend: the real in-memory backend (sign-in / sign-up / refresh).
//   - Provider ports (Stripe / PayPal / Apple / Google): exercised through a
//     ScriptedRunner that asserts the SDK call shape + failure handling.
//   - Maps tile-provider spec (OSM / Mapbox): pure-Dart spec copy of kit/maps'
//     tiled providers — tile URL/geometry, provider resolution, token edge.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/tier1.dart';
import 'package:test/test.dart';

void main() {
  group('SeedAuthBackend — seed', () {
    test('default seed exposes alice and bob without passwords', () {
      final backend = SeedAuthBackend();
      final users = backend.seedUsers();
      expect(users['seed_alice']?['email'], 'alice@showcase.app');
      expect(users['seed_bob']?['email'], 'bob@showcase.app');
      // password is never leaked through the read-only view
      expect(users['seed_alice']!.containsKey('password'), isFalse);
    });
  });

  group('SeedAuthBackend — sign in', () {
    test('correct password succeeds and mints a token', () {
      final backend = SeedAuthBackend();
      final res = backend.signIn('alice@showcase.app', 'seed-alice');

      expect(res.ok, isTrue, reason: '$res');
      expect(res.provider, 'SeedAuthBackend');
      expect(res.userId, 'seed_alice');
      expect(res.email, 'alice@showcase.app');
      expect(res.token, isNotNull);
      expect(res.token, isNotEmpty);
      // the session is observable
      expect(backend.currentUser('seed_alice')?['email'], 'alice@showcase.app');
    });

    test('wrong password fails with a precise error', () {
      final backend = SeedAuthBackend();
      final res = backend.signIn('alice@showcase.app', 'nope');

      expect(res.ok, isFalse);
      expect(res.error, 'wrong password');
      expect(res.token, isNull);
    });

    test('unknown user fails with a precise error', () {
      final backend = SeedAuthBackend();
      final res = backend.signIn('nobody@showcase.app', 'x');

      expect(res.ok, isFalse);
      expect(res.error, 'unknown user');
    });

    test('sign out clears the session', () {
      final backend = SeedAuthBackend();
      backend.signIn('alice@showcase.app', 'seed-alice');
      expect(backend.currentUser('seed_alice'), isNotNull);

      backend.signOut('seed_alice');
      expect(backend.currentUser('seed_alice'), isNull);

      // idempotent: signing out again is a no-op
      backend.signOut('seed_alice');
      expect(backend.currentUser('seed_alice'), isNull);
    });
  });

  group('SeedAuthBackend — sign up', () {
    test('creates a new user and opens a session', () {
      final backend = SeedAuthBackend();
      final res = backend.signUp('carol@showcase.app', 'pw-carol');

      expect(res.ok, isTrue, reason: '$res');
      expect(res.userId, isNotNull);
      expect(res.email, 'carol@showcase.app');
      expect(res.token, isNotEmpty);
      expect(backend.currentUser(res.userId!)?['email'], 'carol@showcase.app');
    });

    test('the new user can sign in independently', () {
      final backend = SeedAuthBackend();
      backend.signUp('carol@showcase.app', 'pw-carol');

      final res = backend.signIn('carol@showcase.app', 'pw-carol');
      expect(res.ok, isTrue);
      expect(res.email, 'carol@showcase.app');
    });

    test('duplicate email is rejected', () {
      final backend = SeedAuthBackend();
      backend.signUp('carol@showcase.app', 'pw-carol');

      final res = backend.signUp('carol@showcase.app', 'other');
      expect(res.ok, isFalse);
      expect(res.error, 'user already exists');
    });

    test('does not collide with seed keys', () {
      final backend = SeedAuthBackend();
      final res = backend.signUp('carol@showcase.app', 'pw-carol');
      expect(res.userId, isNot('seed_alice'));
      expect(res.userId, isNot('seed_bob'));
    });
  });

  group('SeedAuthBackend — token refresh', () {
    test('valid token rotates to a fresh token', () {
      final backend = SeedAuthBackend();
      final auth = backend.signIn('alice@showcase.app', 'seed-alice');

      final refreshed = backend.refreshToken(auth.token!);
      expect(refreshed.ok, isTrue, reason: '$refreshed');
      expect(refreshed.token, isNotEmpty);
      expect(refreshed.token, isNot(auth.token));
      expect(refreshed.userId, 'seed_alice');
      expect(refreshed.email, 'alice@showcase.app');
    });

    test('old token is invalid after refresh', () {
      final backend = SeedAuthBackend();
      final auth = backend.signIn('alice@showcase.app', 'seed-alice');
      backend.refreshToken(auth.token!);

      final again = backend.refreshToken(auth.token!);
      expect(again.ok, isFalse);
      expect(again.error, 'invalid or expired token');
    });

    test('bogus token is rejected', () {
      final backend = SeedAuthBackend();
      final res = backend.refreshToken('not-a-real-token');
      expect(res.ok, isFalse);
      expect(res.error, 'invalid or expired token');
    });

    test('refreshed token keeps the session usable', () {
      final backend = SeedAuthBackend();
      final auth = backend.signIn('alice@showcase.app', 'seed-alice');
      final refreshed = backend.refreshToken(auth.token!);

      // the rotated session is still resolvable by uid
      expect(backend.currentUser(refreshed.userId!)?['email'], 'alice@showcase.app');
    });
  });

  group('Stripe port — call shape', () {
    test('happy path: init -> create -> present succeeds', () {
      final runner = ScriptedRunner([
        (['stripe', 'init'], const CompletedProc(0)),
        (['stripe', 'payment-intents', 'create'], const CompletedProc(0, stdout: 'pi_demo_123')),
        (['stripe', 'payment-sheet', 'present'], const CompletedProc(0, stdout: 'succeeded')),
      ]);

      final res = stripePay(runner, 1999, 'usd');

      expect(runner.callCount, 3, reason: 'stripe port must issue all 3 commands');
      expect(res.ok, isTrue);
      expect(res.provider, 'Stripe');
      expect(res.paymentIntentId, 'pi_demo_123');
    });

    test('create forwards amount, currency, customer in order', () {
      final runner = ScriptedRunner([
        (['stripe', 'init'], const CompletedProc(0)),
        (['stripe', 'payment-intents', 'create', '--amount', '1999', '--currency', 'usd',
          '--customer', 'cust_demo'], const CompletedProc(0, stdout: 'pi_demo_123')),
        (['stripe', 'payment-sheet', 'present'], const CompletedProc(0)),
      ]);

      final res = stripePay(runner, 1999, 'usd');
      expect(res.ok, isTrue);
    });

    test('sheet-present failure is surfaced', () {
      final runner = ScriptedRunner([
        (['stripe', 'init'], const CompletedProc(0)),
        (['stripe', 'payment-intents', 'create'], const CompletedProc(0, stdout: 'pi_demo_456')),
        (['stripe', 'payment-sheet', 'present'], const CompletedProc(1, stderr: 'user cancelled')),
      ]);

      final res = stripePay(runner, 1999, 'usd');
      expect(res.ok, isFalse);
      expect(res.error, contains('user cancelled'));
    });
  });

  group('PayPal port — call shape', () {
    test('happy path: create order -> tokenize', () {
      final runner = ScriptedRunner([
        (['paypal', 'orders', 'create'], const CompletedProc(0, stdout: 'order_demo_1')),
        (['paypal', 'tokens', 'request', '--order', 'order_demo_1'],
            const CompletedProc(0, stdout: 'tok_demo_1')),
      ]);

      final res = paypalOrder(runner, 4999, 'eur');
      expect(res.ok, isTrue);
      expect(res.paymentIntentId, 'order_demo_1');
    });

    test('order create failure is surfaced', () {
      final runner = ScriptedRunner([
        (['paypal', 'orders', 'create'], const CompletedProc(1, stderr: 'network')),
      ]);

      final res = paypalOrder(runner, 4999, 'eur');
      expect(res.ok, isFalse);
      expect(res.error, contains('network'));
    });
  });

  group('Apple SignIn port — call shape', () {
    test('happy path: capability-check -> authorize', () {
      final runner = ScriptedRunner([
        (['apple', 'signin', 'capability-check'], const CompletedProc(0)),
        (['apple', 'signin', 'authorize', '--nonce', 'nonce-abc'],
            const CompletedProc(0, stdout: 'apple_uid')),
      ]);

      final res = appleSignIn(runner, 'nonce-abc');
      expect(res.ok, isTrue);
      expect(res.userId, 'apple_uid');
      expect(res.email, 'relay@apple.example');
    });

    test('missing capability fails (the silent-failure case)', () {
      final runner = ScriptedRunner([
        (['apple', 'signin', 'capability-check'], const CompletedProc(1)),
      ]);

      final res = appleSignIn(runner, 'nonce-abc');
      expect(res.ok, isFalse);
      expect(res.error, contains('capability'));
    });
  });

  group('Google SignIn port — call shape', () {
    test('happy path: initialize -> authenticate', () {
      final runner = ScriptedRunner([
        (['google', 'signin', 'initialize', '--server-client-id-env', 'GOOGLE_SERVER_CLIENT_ID'],
            const CompletedProc(0)),
        (['google', 'signin', 'authenticate', '--nonce', 'nonce-xyz'],
            const CompletedProc(0, stdout: 'google_uid')),
      ]);

      final res = googleSignIn(runner, 'nonce-xyz');
      expect(res.ok, isTrue);
      expect(res.userId, 'google_uid');
      expect(res.email, 'demo@google.example');
    });

    test('authenticate failure is surfaced', () {
      final runner = ScriptedRunner([
        (['google', 'signin', 'initialize'], const CompletedProc(0)),
        (['google', 'signin', 'authenticate'], const CompletedProc(1, stderr: 'cancelled')),
      ]);

      final res = googleSignIn(runner, 'nonce-xyz');
      expect(res.ok, isFalse);
      expect(res.error, contains('cancelled'));
    });
  });

  group('ScriptedRunner — assertion mechanics', () {
    test('extra command beyond expectations throws', () {
      final runner = ScriptedRunner([
        (['x', 'one'], const CompletedProc(0)),
      ]);
      runner.run(['x', 'one']);
      expect(() => runner.run(['x', 'two']), throwsStateError);
    });

    test('wrong command prefix throws', () {
      final runner = ScriptedRunner([
        (['x', 'one'], const CompletedProc(0)),
      ]);
      expect(() => runner.run(['y', 'one']), throwsStateError);
    });
  });

  group('maps tile-provider spec — provider resolution', () {
    test('iOS resolves to Apple Maps', () {
      expect(defaultMapProviderFor('ios'), MapProviderKind.apple);
    });

    test('every non-iOS platform resolves to Google Maps', () {
      for (final p in ['android', 'fuchsia', 'linux', 'macos', 'windows']) {
        expect(defaultMapProviderFor(p), MapProviderKind.google, reason: p);
      }
    });
  });

  group('maps tile-provider spec — OpenStreetMap', () {
    test('standard tile server, 256px tiles, policy-required UA', () {
      final spec = osmTileLayer(userAgentPackageName: 'com.example.test');
      expect(spec.urlTemplate,
          'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
      expect(spec.tileDimension, 256);
      expect(spec.zoomOffset, 0);
      expect(tileUserAgentHeader(spec.userAgentPackageName),
          'flutter_map (com.example.test)');
    });
  });

  group('maps tile-provider spec — Mapbox', () {
    test('512px raster tiles with the public token in the URL', () {
      final spec = mapboxTileLayer(
          accessToken: 'pk.test-token',
          userAgentPackageName: 'com.example.test');
      expect(
        spec.urlTemplate,
        'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/'
        '{z}/{x}/{y}@2x?access_token=pk.test-token',
      );
      expect(spec.tileDimension, 512);
      expect(spec.zoomOffset, -1);
    });

    test('mapType selects the Mapbox style', () {
      expect(mapboxStyleFor('normal'), 'streets-v12');
      expect(mapboxStyleFor('satellite'), 'satellite-v9');
      expect(mapboxStyleFor('hybrid'), 'satellite-streets-v12');
      expect(mapboxStyleFor('terrain'), 'outdoors-v12');
    });

    test('missing token is rejected eagerly, not as silent tile 401s', () {
      expect(
        () => mapboxTileLayer(
            accessToken: '', userAgentPackageName: 'com.example.test'),
        throwsArgumentError,
      );
    });
  });

  group('bundled self-check', () {
    test('runTier1Suites passes every suite', () {
      final result = runTier1Suites();
      expect(result.failed, isEmpty, reason: result.failed.join('\n'));
      expect(result.passed, hasLength(7));
      expect(result.allPassed, isTrue);
    });
  });

  group('promoteTier1 — the only tier writer (13.3)', () {
    test('sets port-tested, records evidence, and is byte-stable on re-run', () {
      final tmp = Directory.systemTemp.createTempSync('tier1_promote');
      addTearDown(() => tmp.deleteSync(recursive: true));
      Directory('${tmp.path}/appboxd/lib').createSync(recursive: true);
      Directory('${tmp.path}/config').createSync(recursive: true);
      // the digest is over the suite file itself — copy the real one
      File('lib/tier1.dart').copySync('${tmp.path}/appboxd/lib/tier1.dart');
      File('${tmp.path}/config/kit-registry.json').writeAsStringSync(
          '{"kits":[{"dir":"auth","providers":['
          '{"name":"SeedAuthBackend","verification":"stub"},'
          '{"name":"Apple SignIn","verification":"stub"}]}]}');

      final bumped = promoteTier1(
        [('auth', 'SeedAuthBackend'), ('auth', 'Apple SignIn')],
        repoRoot: tmp.path,
      );
      expect(bumped, 2);

      final reg = jsonDecode(
          File('${tmp.path}/config/kit-registry.json').readAsStringSync());
      for (final p in reg['kits'][0]['providers']) {
        expect(p['verification'], 'port-tested');
      }
      final ledger = jsonDecode(
              File('${tmp.path}/config/evidence.json').readAsStringSync())['ledger']
          as Map<String, dynamic>;
      final rec = ledger['auth/SeedAuthBackend'] as Map<String, dynamic>;
      expect(rec['tier'], 'port-tested');
      expect(rec['suite'], 'appboxd/lib/tier1.dart');
      expect(rec['digest'], startsWith('sha256:'));

      // idempotent: same suite content -> nothing changes, ran_at preserved
      final before = File('${tmp.path}/config/evidence.json').readAsStringSync();
      final bumpedAgain = promoteTier1(
        [('auth', 'SeedAuthBackend'), ('auth', 'Apple SignIn')],
        repoRoot: tmp.path,
      );
      expect(bumpedAgain, 0);
      expect(File('${tmp.path}/config/evidence.json').readAsStringSync(), before);
    });
  });
}
