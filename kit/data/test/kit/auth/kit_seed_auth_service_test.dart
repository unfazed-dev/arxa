import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_data/assets/kit_asset_reader.dart';
import 'package:appbox_kit_data/auth/kit_auth_types.dart';
import 'package:appbox_kit_data/auth/seed/kit_seed_auth_service.dart';
import 'package:appbox_kit_data/ids/kit_id_service.dart';
import 'package:appbox_kit_data/repositories/seed/kit_seed_persistence.dart';
import 'package:appbox_kit_data/repositories/seed/kit_seed_store.dart';

/// KitSeedAuthService tests, backed by a real [KitSeedStore] +
/// [KitNoPersistence] and a [KitMemoryAssetReader] (same approach as
/// kit_fixture_loader_test.dart — no mocks).
///
/// Branches under test:
/// - `initialize()` seeds fixture users into `kit_auth_users`; signing in
///   with a fixture user's email resolves to the CANONICAL id of its seed
///   key — the fixture-ownership synergy that lets other fixtures reference
///   `"owner": "user-1"` and land on the same id the session carries.
/// - `session$` emits `null` on listen, a session after sign-in, `null`
///   again after `signOut`.
/// - `signInWithEmailPassword` auto-creates unknown identities; signing in
///   with the same email twice yields the same user id (determinism).
/// - OTP: `requestOtp` throws `KitAuthException` when given both or neither
///   of email/phone; `requestOtp(email)` then `confirmOtp(email, anyCode)`
///   yields a session for that email.
/// - Google/Apple: instant sessions with distinct, deterministic ids; each
///   called twice returns the same id.
/// - `signInAnonymously`: `isAnonymous` is true; two calls produce different
///   ids.
/// - Users survive in the store: after any sign-in, `tableSnapshot` on
///   `kit_auth_users` contains the resolved row.
void main() {
  final idService = KitIdService();

  KitSeedStore makeStore() => KitSeedStore(persistence: KitNoPersistence());

  KitSeedAuthService makeService({
    KitSeedStore? store,
    String? fakeUsersAsset,
    Map<String, String>? assets,
  }) =>
      KitSeedAuthService(
        store: store ?? makeStore(),
        idService: idService,
        fakeUsersAsset: fakeUsersAsset,
        // Never read when fakeUsersAsset is null (initialize() returns early),
        // so an empty reader is a safe placeholder for the no-asset cases.
        assetReader: KitMemoryAssetReader(assets ?? <String, String>{}),
      );

  group('initialize()', () {
    test(
        'seeds fixture users; signing in by email resolves to the canonical seed-key id',
        () async {
      final assets = {
        'assets/seed/kit_auth_users.json': jsonEncode([
          {'id': 'user-1', 'email': 'Alice@Example.com'},
        ]),
      };
      final service = makeService(
        fakeUsersAsset: 'assets/seed/kit_auth_users.json',
        assets: assets,
      );
      await service.initialize();

      final session = await service.signInWithEmailPassword(
        email: 'alice@example.com',
        password: 'anything',
      );

      final expectedId = idService.canonicalId('kit_auth_users', 'user-1');
      expect(session.user.id, expectedId);
    });

    test('no-ops when fakeUsersAsset is null', () async {
      final service = makeService();
      await service.initialize();
      expect(service.currentSession, isNull);
    });
  });

  test('session\$ emits null on listen, then session after sign-in, then null after signOut',
      () async {
    final service = makeService();

    final expectation = expectLater(
      service.session$,
      emitsInOrder([
        isNull,
        isA<KitAuthSession>(),
        isNull,
      ]),
    );

    await service.signInWithEmailPassword(
      email: 'bob@example.com',
      password: 'whatever',
    );
    await service.signOut();

    await expectation;
  });

  group('signInWithEmailPassword', () {
    test('auto-creates unknown identities', () async {
      final service = makeService();

      final session = await service.signInWithEmailPassword(
        email: 'new-user@example.com',
        password: 'anything',
      );

      expect(session.user.email, 'new-user@example.com');
      expect(session.user.id, isNotEmpty);
    });

    test('same email twice yields the same user id', () async {
      final service = makeService();

      final first = await service.signInWithEmailPassword(
        email: 'dup@example.com',
        password: 'p1',
      );
      final second = await service.signInWithEmailPassword(
        email: 'dup@example.com',
        password: 'pw-totally-different',
      );

      expect(second.user.id, first.user.id);
    });
  });

  group('OTP', () {
    test('requestOtp throws when given both email and phone', () async {
      final service = makeService();
      await expectLater(
        service.requestOtp(email: 'a@example.com', phone: '+15551234567'),
        throwsA(isA<KitAuthException>()),
      );
    });

    test('requestOtp throws when given neither email nor phone', () async {
      final service = makeService();
      await expectLater(
        service.requestOtp(),
        throwsA(isA<KitAuthException>()),
      );
    });

    test('requestOtp(email) then confirmOtp(email, anyCode) yields a session for that email',
        () async {
      final service = makeService();

      await service.requestOtp(email: 'otp-user@example.com');
      final session = await service.confirmOtp(
        email: 'otp-user@example.com',
        code: '000000',
      );

      expect(session.user.email, 'otp-user@example.com');
    });
  });

  group('Google / Apple', () {
    test('signInWithGoogle grants an instant session with a deterministic id',
        () async {
      final service = makeService();

      final first = await service.signInWithGoogle();
      final second = await service.signInWithGoogle();

      expect(first.user.email, 'google-user@seed.local');
      expect(first.user.displayName, 'Google Seed User');
      expect(second.user.id, first.user.id);
    });

    test('signInWithApple grants an instant session with a deterministic id',
        () async {
      final service = makeService();

      final first = await service.signInWithApple();
      final second = await service.signInWithApple();

      expect(first.user.email, 'apple-user@seed.local');
      expect(first.user.displayName, 'Apple Seed User');
      expect(second.user.id, first.user.id);
    });

    test('Google and Apple resolve to distinct ids', () async {
      final service = makeService();

      final google = await service.signInWithGoogle();
      final apple = await service.signInWithApple();

      expect(google.user.id, isNot(apple.user.id));
    });
  });

  test('signInAnonymously marks isAnonymous true; two calls yield different ids',
      () async {
    final service = makeService();

    final first = await service.signInAnonymously();
    final second = await service.signInAnonymously();

    expect(first.user.isAnonymous, isTrue);
    expect(second.user.isAnonymous, isTrue);
    expect(second.user.id, isNot(first.user.id));
  });

  test('users survive in the store after sign-in', () async {
    final store = makeStore();
    final service = makeService(store: store);

    final session = await service.signInWithEmailPassword(
      email: 'persisted@example.com',
      password: 'anything',
    );

    final rows = store.tableSnapshot('kit_auth_users');
    expect(rows[session.user.id], isNotNull);
    expect(rows[session.user.id]!['email'], 'persisted@example.com');
  });
}
