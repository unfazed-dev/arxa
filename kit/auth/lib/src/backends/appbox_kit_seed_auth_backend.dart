import 'dart:async';

import '../models/appbox_kit_auth_credentials.dart';
import '../models/appbox_kit_auth_failure.dart';
import '../models/appbox_kit_auth_result.dart';
import '../models/appbox_kit_auth_session.dart';
import '../models/appbox_kit_auth_user.dart';
import '../service/appbox_kit_auth_service.dart';

class _SeededUser {
  final String email;
  final String password;

  const _SeededUser(this.email, this.password);
}

class _Session {
  final String userId;
  final String email;
  final String token;

  const _Session(this.userId, this.email, this.token);
}

/// Default seed — deterministic local showcase credentials. Never a real
/// credential store.
const _defaultSeed = <String, _SeededUser>{
  'seed_alice': _SeededUser('alice@showcase.app', 'seed-alice'),
  'seed_bob': _SeededUser('bob@showcase.app', 'seed-bob'),
};

/// In-memory seeded auth backend. No device, no external process, no real
/// account. Powers the seeded-data story the product promises (the showcase
/// depends on it). This is the genuine port of the `appboxd/lib/tier1.dart`
/// AppBoxKitSeedAuthBackend spec into the kit's [AppBoxKitAuthService] interface — same
/// seeded accounts, same failure semantics, same deterministic token minting.
///
/// Determinism is the point: seeded uids (`seed_alice`, `seed_bob`), sign-up
/// uids (`user_1`, `user_2`, …) and session tokens (`tok_1`, `tok_2`, …) are
/// minted from monotonic counters, so refresh rotation is observable and
/// tests never flake. Email matching is exact (after trim), mirroring the
/// tier1 spec; sign-up applies no password-strength policy.
class AppBoxKitSeedAuthBackend implements AppBoxKitAuthService {
  final Map<String, _SeededUser> _users = {};
  final Map<String, _Session> _sessionsByUid = {}; // userId -> session
  final Map<String, _Session> _sessionsByToken = {}; // token -> session
  final Map<String, String> _providerByUid = {}; // userId -> provider tag
  final StreamController<AppBoxKitAuthUser?> _controller =
      StreamController<AppBoxKitAuthUser?>.broadcast();

  var _tokenSeq = 0;
  var _uidSeq = 0;
  String? _currentUid;
  bool _disposed = false;

  AppBoxKitSeedAuthBackend() {
    _users.addAll(_defaultSeed);
  }

  @override
  Stream<AppBoxKitAuthUser?> get authStateChanges async* {
    _assertUsable();
    yield currentUser;
    yield* _controller.stream;
  }

  /// The most recently signed-in user, or null. Mirrors the tier1 spec's
  /// per-uid sessions: sign-ins for other uids do not end earlier sessions,
  /// but the kit's single-user stream tracks the latest one.
  @override
  AppBoxKitAuthUser? get currentUser {
    final uid = _currentUid;
    if (uid == null) return null;
    final session = _sessionsByUid[uid];
    if (session == null) return null;
    return _userFor(uid, session.email);
  }

  /// The tier1 spec's `currentUser(uid)`: the signed-in user for [uid], or
  /// null if that uid has no live session.
  AppBoxKitAuthUser? currentUserFor(String uid) {
    final session = _sessionsByUid[uid];
    if (session == null) return null;
    return _userFor(uid, session.email);
  }

  /// Read-only view of the seeded users (no passwords), as uid → {email}.
  Map<String, Map<String, String>> seedUsers() => {
        for (final e in _users.entries) e.key: {'email': e.value.email},
      };

  @override
  Future<AppBoxKitAuthResult> signUp(AppBoxKitEmailPasswordCredentials credentials) async {
    _assertUsable();
    final email = credentials.email.trim();
    for (final rec in _users.values) {
      if (rec.email == email) {
        return const AppBoxKitAuthFailure(
          AppBoxKitAuthFailureReason.emailAlreadyInUse,
          message: 'user already exists',
        );
      }
    }
    final uid = 'user_${++_uidSeq}';
    _users[uid] = _SeededUser(email, credentials.password);
    return _emitSession(_openSession(uid, email));
  }

  @override
  Future<AppBoxKitAuthResult> signIn(AppBoxKitEmailPasswordCredentials credentials) async {
    _assertUsable();
    final email = credentials.email.trim();
    String? uid;
    _SeededUser? rec;
    for (final entry in _users.entries) {
      if (entry.value.email == email) {
        uid = entry.key;
        rec = entry.value;
        break;
      }
    }
    if (rec == null) {
      return const AppBoxKitAuthFailure(
        AppBoxKitAuthFailureReason.userNotFound,
        message: 'unknown user',
      );
    }
    if (rec.password != credentials.password) {
      return const AppBoxKitAuthFailure(
        AppBoxKitAuthFailureReason.invalidCredentials,
        message: 'wrong password',
      );
    }
    return _emitSession(_openSession(uid!, email));
  }

  /// Rotate a session token (the tier1 spec's `refreshToken`). The old token
  /// is invalidated; a fresh one is minted for the same user and becomes the
  /// current session. Unknown or already-rotated tokens fail with
  /// [AppBoxKitAuthFailureReason.tokenExpired].
  Future<AppBoxKitAuthResult> refreshToken(String token) async {
    _assertUsable();
    final prev = _sessionsByToken.remove(token);
    if (prev == null) {
      return const AppBoxKitAuthFailure(
        AppBoxKitAuthFailureReason.tokenExpired,
        message: 'invalid or expired token',
      );
    }
    return _emitSession(_openSession(prev.userId, prev.email));
  }

  @override
  Future<AppBoxKitAuthResult> signInWithApple() => _resolveProviderUser(
        'apple',
        'apple_demo_user',
        'relay@apple.example',
      );

  @override
  Future<AppBoxKitAuthResult> signInWithGoogle() => _resolveProviderUser(
        'google',
        'google_demo_user',
        'demo@google.example',
      );

  @override
  Future<void> signOut() async {
    _assertUsable();
    final uid = _currentUid;
    if (uid != null) {
      final session = _sessionsByUid.remove(uid);
      if (session != null) _sessionsByToken.remove(session.token);
      _currentUid = null;
    }
    _controller.add(null);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _controller.close();
  }

  /// The seed backend's OAuth story: deterministic demo identities matching
  /// the tier1 `appleSignIn` / `googleSignIn` fixtures — a real native flow
  /// is what the Apple/Google [AppBoxKitOAuthProvider]s are for.
  Future<AppBoxKitAuthResult> _resolveProviderUser(
    String provider,
    String uid,
    String email,
  ) async {
    _assertUsable();
    _users.putIfAbsent(uid, () => _SeededUser(email, ''));
    return _emitSession(_openSession(uid, email, provider: provider));
  }

  _Session _openSession(String uid, String email, {String? provider}) {
    final token = 'tok_${++_tokenSeq}';
    final session = _Session(uid, email, token);
    _sessionsByUid[uid] = session;
    _sessionsByToken[token] = session;
    _providerByUid[uid] = provider ?? 'seed';
    return session;
  }

  AppBoxKitAuthResult _emitSession(_Session session) {
    final user = _userFor(session.userId, session.email);
    _currentUid = session.userId;
    _controller.add(user);
    return AppBoxKitAuthSuccess(AppBoxKitAuthSession(
      user: user,
      accessToken: session.token,
      refreshToken: session.token,
    ));
  }

  AppBoxKitAuthUser _userFor(String uid, String email) => AppBoxKitAuthUser(
        id: uid,
        email: email,
        metadata: {'provider': _providerByUid[uid] ?? 'seed'},
      );

  void _assertUsable() {
    if (_disposed) {
      throw StateError('AppBoxKitSeedAuthBackend used after dispose()');
    }
  }
}
