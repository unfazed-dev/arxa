import 'dart:async';

import '../models/auth_credentials.dart';
import '../models/auth_failure.dart';
import '../models/auth_result.dart';
import '../models/auth_session.dart';
import '../models/auth_user.dart';
import 'kit_auth_service.dart';

/// The default backend: a real, process-lifetime identity store with no
/// persistence and no network. Good enough to build and demo the full auth UI
/// against before the Seed / Supabase / OAuth backends land.
///
/// This DOES check passwords (unlike a pure fake) — a wrong password is
/// [AuthFailureReason.invalidCredentials] — but it is NOT secure: passwords
/// live in memory in plaintext and are gone on restart. Never ship it as the
/// production backend.
///
/// Ids are deterministic (`local:<normalised-email>`), so the same email
/// always resolves to the same [AuthUser.id] within and across runs.
class InMemoryKitAuthService implements KitAuthService {
  /// Minimum password length accepted by [signUp].
  final int minPasswordLength;

  /// When set, sessions are minted with `expiresAt = now + sessionTtl`. Purely
  /// informational here (nothing auto-signs-out); it lets hosts and tests see
  /// a realistic [AuthSession.expiresAt].
  final Duration? sessionTtl;

  final Map<String, _StoredUser> _usersByEmail = {};
  final StreamController<AuthUser?> _controller =
      StreamController<AuthUser?>.broadcast();

  AuthSession? _session;
  bool _disposed = false;

  InMemoryKitAuthService({
    this.minPasswordLength = 6,
    this.sessionTtl,
  });

  @override
  Stream<AuthUser?> get authStateChanges async* {
    _assertUsable();
    yield _session?.user;
    yield* _controller.stream;
  }

  @override
  AuthUser? get currentUser => _session?.user;

  @override
  Future<AuthResult> signUp(EmailPasswordCredentials credentials) async {
    _assertUsable();
    final email = credentials.email.trim().toLowerCase();
    if (credentials.password.length < minPasswordLength) {
      return AuthFailure(
        AuthFailureReason.weakPassword,
        message: 'Password must be at least $minPasswordLength characters',
      );
    }
    if (_usersByEmail.containsKey(email)) {
      return const AuthFailure(
        AuthFailureReason.emailAlreadyInUse,
        message: 'An account already exists for that email',
      );
    }
    final user = AuthUser(id: _idFor(email), email: email);
    _usersByEmail[email] = _StoredUser(user, credentials.password);
    return _emitSession(user);
  }

  @override
  Future<AuthResult> signIn(EmailPasswordCredentials credentials) async {
    _assertUsable();
    final email = credentials.email.trim().toLowerCase();
    final stored = _usersByEmail[email];
    if (stored == null) {
      return const AuthFailure(
        AuthFailureReason.userNotFound,
        message: 'No account for that email',
      );
    }
    if (stored.password != credentials.password) {
      return const AuthFailure(
        AuthFailureReason.invalidCredentials,
        message: 'Incorrect password',
      );
    }
    return _emitSession(stored.user);
  }

  @override
  Future<AuthResult> signInWithApple() =>
      _resolveProviderUser('apple', 'apple-user@local', 'Apple User');

  @override
  Future<AuthResult> signInWithGoogle() =>
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

  Future<AuthResult> _resolveProviderUser(
    String provider,
    String email,
    String displayName,
  ) async {
    _assertUsable();
    final normalized = email.toLowerCase();
    final existing = _usersByEmail[normalized];
    final user = existing?.user ??
        AuthUser(
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

  AuthResult _emitSession(AuthUser user) {
    final session = AuthSession(
      user: user,
      accessToken: 'local-token-${user.id}',
      expiresAt: sessionTtl == null ? null : DateTime.now().add(sessionTtl!),
    );
    _session = session;
    _controller.add(user);
    return AuthSuccess(session);
  }

  String _idFor(String email) => 'local:$email';

  void _assertUsable() {
    if (_disposed) {
      throw StateError('InMemoryKitAuthService used after dispose()');
    }
  }
}

class _StoredUser {
  final AuthUser user;
  final String password;

  const _StoredUser(this.user, this.password);
}
