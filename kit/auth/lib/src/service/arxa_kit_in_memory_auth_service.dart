import 'dart:async';

import '../models/arxa_kit_auth_credentials.dart';
import '../models/arxa_kit_auth_failure.dart';
import '../models/arxa_kit_auth_result.dart';
import '../models/arxa_kit_auth_session.dart';
import '../models/arxa_kit_auth_user.dart';
import 'arxa_kit_auth_service.dart';

/// The default backend: a real, process-lifetime identity store with no
/// persistence and no network. Good enough to build and demo the full auth UI
/// against before the Seed / Supabase / OAuth backends land.
///
/// This DOES check passwords (unlike a pure fake) — a wrong password is
/// [ArxaKitAuthFailureReason.invalidCredentials] — but it is NOT secure: passwords
/// live in memory in plaintext and are gone on restart. Never ship it as the
/// production backend.
///
/// Ids are deterministic (`local:<normalised-email>`), so the same email
/// always resolves to the same [ArxaKitAuthUser.id] within and across runs.
class InMemoryArxaKitAuthService implements ArxaKitAuthService {
  /// Minimum password length accepted by [signUp].
  final int minPasswordLength;

  /// When set, sessions are minted with `expiresAt = now + sessionTtl`. Purely
  /// informational here (nothing auto-signs-out); it lets hosts and tests see
  /// a realistic [ArxaKitAuthSession.expiresAt].
  final Duration? sessionTtl;

  final Map<String, _StoredUser> _usersByEmail = {};
  final StreamController<ArxaKitAuthUser?> _controller =
      StreamController<ArxaKitAuthUser?>.broadcast();

  ArxaKitAuthSession? _session;
  bool _disposed = false;

  InMemoryArxaKitAuthService({
    this.minPasswordLength = 6,
    this.sessionTtl,
  });

  @override
  Stream<ArxaKitAuthUser?> get authStateChanges async* {
    _assertUsable();
    yield _session?.user;
    yield* _controller.stream;
  }

  @override
  ArxaKitAuthUser? get currentUser => _session?.user;

  @override
  Future<ArxaKitAuthResult> signUp(ArxaKitEmailPasswordCredentials credentials) async {
    _assertUsable();
    final email = credentials.email.trim().toLowerCase();
    if (credentials.password.length < minPasswordLength) {
      return ArxaKitAuthFailure(
        ArxaKitAuthFailureReason.weakPassword,
        message: 'Password must be at least $minPasswordLength characters',
      );
    }
    if (_usersByEmail.containsKey(email)) {
      return const ArxaKitAuthFailure(
        ArxaKitAuthFailureReason.emailAlreadyInUse,
        message: 'An account already exists for that email',
      );
    }
    final user = ArxaKitAuthUser(id: _idFor(email), email: email);
    _usersByEmail[email] = _StoredUser(user, credentials.password);
    return _emitSession(user);
  }

  @override
  Future<ArxaKitAuthResult> signIn(ArxaKitEmailPasswordCredentials credentials) async {
    _assertUsable();
    final email = credentials.email.trim().toLowerCase();
    final stored = _usersByEmail[email];
    if (stored == null) {
      return const ArxaKitAuthFailure(
        ArxaKitAuthFailureReason.userNotFound,
        message: 'No account for that email',
      );
    }
    if (stored.password != credentials.password) {
      return const ArxaKitAuthFailure(
        ArxaKitAuthFailureReason.invalidCredentials,
        message: 'Incorrect password',
      );
    }
    return _emitSession(stored.user);
  }

  @override
  Future<ArxaKitAuthResult> signInWithApple() =>
      _resolveProviderUser('apple', 'apple-user@local', 'Apple User');

  @override
  Future<ArxaKitAuthResult> signInWithGoogle() =>
      _resolveProviderUser('google', 'google-user@local', 'Google User');

  @override
  Future<void> signOut() async {
    _assertUsable();
    _session = null;
    _controller.add(null);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _controller.close();
  }

  Future<ArxaKitAuthResult> _resolveProviderUser(
    String provider,
    String email,
    String displayName,
  ) async {
    _assertUsable();
    final normalized = email.toLowerCase();
    final existing = _usersByEmail[normalized];
    final user = existing?.user ??
        ArxaKitAuthUser(
          id: _idFor(normalized),
          email: normalized,
          displayName: displayName,
          metadata: {'provider': provider},
        );
    // OAuth users are stored without a usable password (empty) — they can only
    // return through the same provider path.
    _usersByEmail[normalized] = _StoredUser(user, existing?.password ?? '');
    return _emitSession(user);
  }

  ArxaKitAuthResult _emitSession(ArxaKitAuthUser user) {
    final session = ArxaKitAuthSession(
      user: user,
      accessToken: 'local-token-${user.id}',
      expiresAt: sessionTtl == null ? null : DateTime.now().add(sessionTtl!),
    );
    _session = session;
    _controller.add(user);
    return ArxaKitAuthSuccess(session);
  }

  String _idFor(String email) => 'local:$email';

  void _assertUsable() {
    if (_disposed) {
      throw StateError('InMemoryArxaKitAuthService used after dispose()');
    }
  }
}

class _StoredUser {
  final ArxaKitAuthUser user;
  final String password;

  const _StoredUser(this.user, this.password);
}
