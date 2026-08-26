import 'dart:convert';

import 'package:rxdart/rxdart.dart';

import '../../assets/arxa_kit_asset_reader.dart';

import '../../ids/arxa_kit_id_service.dart';
import '../../repositories/seed/arxa_kit_seed_store.dart';
import '../arxa_kit_auth_service.dart';
import '../arxa_kit_auth_types.dart';

/// Fake, in-memory [ArxaKitAuthService] for [ArxaKitDataBackend.seed] hosts.
///
/// THIS IS NOT REAL AUTHENTICATION. [signUpWithEmailPassword] and
/// [signInWithEmailPassword] succeed for ANY password — the password is
/// never checked against anything — and [confirmOtp] accepts ANY code
/// (`000000` is the conventional one to type in host UIs/tests). Every
/// sign-in method *resolves* an identity rather than authenticating one: it
/// looks up [kArxaKitAuthUsersTable] rows by email (or phone), matching
/// case-insensitively, and auto-creates a row when none exists. Sessions
/// never carry a token — `accessToken`/`expiresAt` are always null — because
/// nothing outside the auth seam should ever need to verify a fake session.
///
/// Users persist in the [ArxaKitSeedStore]'s reserved [kArxaKitAuthUsersTable] (and
/// so survive a snapshot reload), which is what makes fixture-authored
/// owners (e.g. `"owner": "user-1"`) resolve to a stable id across boots.
/// The session itself is deliberately NOT persisted — boot is always signed
/// out, only the users survive.
class ArxaKitSeedAuthService implements ArxaKitAuthService {
  final ArxaKitSeedStore store;
  final ArxaKitIdService idService;
  final String? fakeUsersAsset;
  final ArxaKitAssetReader assetReader;

  final BehaviorSubject<ArxaKitAuthSession?> _session$ =
      BehaviorSubject<ArxaKitAuthSession?>.seeded(null);

  /// The identity [requestOtp] was last called for, so a caller that omits
  /// email/phone on [confirmOtp] still resolves the pending target. Real
  /// callers normally pass the same email/phone to both.
  String? _pendingOtpEmail;
  String? _pendingOtpPhone;

  ArxaKitSeedAuthService({
    required this.store,
    required this.idService,
    this.fakeUsersAsset,
    required this.assetReader,
  });

  /// Loads [fakeUsersAsset] (a JSON array of user rows keyed by seed key, in
  /// the same hand-authored spirit as fixture files) and upserts each into
  /// [kArxaKitAuthUsersTable], canonicalizing its `id` via [idService]. Parsed
  /// inline rather than through `ArxaKitFixtureLoader` — that loader demands a
  /// registered [ArxaKitTableSchema], and this table is deliberately unregistered.
  /// No-op when [fakeUsersAsset] is null.
  Future<void> initialize() async {
    final asset = fakeUsersAsset;
    if (asset == null) return;

    final raw = await assetReader.readString(asset);
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw ArgumentError('Fixture "$asset" must be a JSON array of rows');
    }

    for (final entry in decoded) {
      if (entry is! Map) {
        throw ArgumentError('Fixture "$asset" contains a non-object row');
      }
      final row = Map<String, dynamic>.from(entry);
      final seedKey = row['id'];
      if (seedKey == null) {
        throw ArgumentError('Fixture "$asset" has a row with no "id"');
      }

      await _upsertUserRow(ArxaKitAuthUser(
        id: idService.canonicalId(kArxaKitAuthUsersTable, seedKey),
        email: row['email'] as String?,
        phone: row['phone'] as String?,
        displayName: row['display_name'] as String?,
        isAnonymous: row['is_anonymous'] as bool? ?? false,
        metadata: (row['metadata'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ));
    }
  }

  @override
  Stream<ArxaKitAuthSession?> get session$ => _session$.stream;

  @override
  ArxaKitAuthSession? get currentSession => _session$.value;

  @override
  Future<ArxaKitAuthSession> signUpWithEmailPassword({
    required String email,
    required String password,
  }) =>
      // Fake: password is intentionally never checked. See class doc.
      _resolveAndEmit(email: email);

  @override
  Future<ArxaKitAuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) =>
      // Fake: succeeds for ANY password. See class doc.
      _resolveAndEmit(email: email);

  @override
  Future<void> requestOtp({String? email, String? phone}) async {
    if ((email == null) == (phone == null)) {
      throw const ArxaKitAuthException(
        'requestOtp requires exactly one of email or phone',
        code: 'invalid-otp-target',
      );
    }
    // Fake: no code is actually sent anywhere; just remember the pending
    // identity for confirmOtp.
    _pendingOtpEmail = email;
    _pendingOtpPhone = phone;
  }

  @override
  Future<ArxaKitAuthSession> confirmOtp({
    String? email,
    String? phone,
    required String code,
  }) =>
      // Fake: accepts ANY code — `000000` is the conventional one. See
      // class doc.
      _resolveAndEmit(
        email: email ?? _pendingOtpEmail,
        phone: phone ?? _pendingOtpPhone,
      );

  @override
  Future<ArxaKitAuthSession> signInWithGoogle() => _resolveAndEmit(
        email: 'google-user@seed.local',
        displayName: 'Google Seed User',
      );

  @override
  Future<ArxaKitAuthSession> signInWithApple() => _resolveAndEmit(
        email: 'apple-user@seed.local',
        displayName: 'Apple Seed User',
      );

  @override
  Future<ArxaKitAuthSession> signInAnonymously() async {
    // Row count (not Random/DateTime) gives a deterministic, unique-per-call
    // seed key without any extra mutable state on this service.
    final count = store.tableSnapshot(kArxaKitAuthUsersTable).length;
    final user = ArxaKitAuthUser(
      id: idService.canonicalId(kArxaKitAuthUsersTable, 'anon-$count'),
      isAnonymous: true,
    );
    await _upsertUserRow(user);
    final session = ArxaKitAuthSession(user: user);
    _session$.add(session);
    return session;
  }

  @override
  Future<void> signOut() async {
    _session$.add(null);
  }

  @override
  Future<void> dispose() async {
    // Fire-and-forget the close: awaiting `_session$.close()` deadlocks a
    // testWidgets FakeAsync zone, because rxdart's close waits for in-flight
    // dispatch to drain and the fake clock never advances on its own. The
    // in-memory store is dropped by `arxaKitLocator.reset()` regardless.
    // ignore: unawaited_futures
    _session$.close();
  }

  /// Resolves or creates the identity named by [email]/[phone], emits the
  /// resulting session, and returns it. Shared by every sign-in path — the
  /// only real difference between them is which identity they name.
  Future<ArxaKitAuthSession> _resolveAndEmit({
    String? email,
    String? phone,
    String? displayName,
  }) async {
    final user = await _resolveOrCreateUser(
      email: email,
      phone: phone,
      displayName: displayName,
    );
    final session = ArxaKitAuthSession(user: user);
    _session$.add(session);
    return session;
  }

  /// Looks up [kArxaKitAuthUsersTable] for a row matching [email]/[phone]
  /// case-insensitively; auto-creates one when no match exists. The id of an
  /// auto-created row is minted from `email ?? phone ?? '<provider>-user'`,
  /// so the same identity always resolves to the same id (determinism).
  Future<ArxaKitAuthUser> _resolveOrCreateUser({
    String? email,
    String? phone,
    String? displayName,
  }) async {
    final normalizedEmail = email?.toLowerCase();
    final normalizedPhone = phone?.toLowerCase();

    for (final row in store.tableSnapshot(kArxaKitAuthUsersTable).values) {
      final rowEmail = (row['email'] as String?)?.toLowerCase();
      final rowPhone = (row['phone'] as String?)?.toLowerCase();
      final emailMatches = normalizedEmail != null && rowEmail == normalizedEmail;
      final phoneMatches = normalizedPhone != null && rowPhone == normalizedPhone;
      if (emailMatches || phoneMatches) {
        return _userFromRow(row);
      }
    }

    final key = email ?? phone;
    if (key == null) {
      // Only reachable via confirmOtp with no pending requestOtp — refuse
      // rather than silently sign in a phantom user (matches the Appwrite
      // impl's behavior).
      throw const ArxaKitAuthException(
        'confirmOtp has no pending identity — call requestOtp first, or '
        'pass the same email/phone used there',
        code: 'invalid-otp-target',
      );
    }
    final user = ArxaKitAuthUser(
      id: idService.canonicalId(kArxaKitAuthUsersTable, key),
      email: email,
      phone: phone,
      displayName: displayName,
    );
    await _upsertUserRow(user);
    return user;
  }

  Future<void> _upsertUserRow(ArxaKitAuthUser user) =>
      store.upsertRow(kArxaKitAuthUsersTable, {
        'id': user.id,
        'email': user.email,
        'phone': user.phone,
        'display_name': user.displayName,
        'is_anonymous': user.isAnonymous,
        'metadata': user.metadata,
      });

  ArxaKitAuthUser _userFromRow(Map<String, dynamic> row) => ArxaKitAuthUser(
        id: row['id'] as String,
        email: row['email'] as String?,
        phone: row['phone'] as String?,
        displayName: row['display_name'] as String?,
        isAnonymous: row['is_anonymous'] as bool? ?? false,
        metadata: (row['metadata'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      );
}
