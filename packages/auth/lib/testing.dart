/// Scriptable fake for `appbox_kit_auth`. Import ONLY from tests / storybook:
///
/// ```dart
/// import 'package:appbox_kit_auth/testing.dart';
/// ```
library;

import 'dart:async';

import 'src/models/auth_credentials.dart';
import 'src/models/auth_failure.dart';
import 'src/models/auth_result.dart';
import 'src/models/auth_session.dart';
import 'src/models/auth_user.dart';
import 'src/service/kit_auth_service.dart';

export 'src/models/auth_credentials.dart';
export 'src/models/auth_failure.dart';
export 'src/models/auth_result.dart';
export 'src/models/auth_session.dart';
export 'src/models/auth_user.dart';

/// A [KitAuthService] whose outcomes and state transitions you drive.
///
/// Each auth method returns the next entry of [scriptedResults] (falling back
/// to [defaultResult]); an [AuthSuccess] also pushes its user onto
/// [authStateChanges]. Beyond scripting, the control methods let a test drive
/// the stream directly — including [expireSession], which emits the signed-out
/// state a token expiry produces at runtime.
class FakeKitAuthService implements KitAuthService {
  /// Results handed out by the auth methods, in order.
  final List<AuthResult> scriptedResults;

  /// Returned once [scriptedResults] is exhausted.
  final AuthResult defaultResult;

  final StreamController<AuthUser?> _controller =
      StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;
  int _cursor = 0;
  bool _disposed = false;

  // Call records for assertions.
  final List<EmailPasswordCredentials> signUpCalls = [];
  final List<EmailPasswordCredentials> signInCalls = [];
  int appleCalls = 0;
  int googleCalls = 0;
  int signOutCalls = 0;

  FakeKitAuthService({
    AuthUser? initialUser,
    List<AuthResult>? scriptedResults,
    AuthResult? defaultResult,
  })  : scriptedResults = scriptedResults ?? const [],
        defaultResult = defaultResult ?? _defaultSuccess,
        _currentUser = initialUser;

  /// Starts signed in as [user]; every method succeeds with a session for it.
  factory FakeKitAuthService.signedIn(AuthUser user) => FakeKitAuthService(
        initialUser: user,
        defaultResult: AuthSuccess(AuthSession(user: user)),
      );

  /// Starts signed out; every method succeeds with a synthetic user.
  factory FakeKitAuthService.signedOut() => FakeKitAuthService();

  /// Every method fails with [reason].
  factory FakeKitAuthService.alwaysFails(
    AuthFailureReason reason, {
    String message = 'fake failure',
  }) =>
      FakeKitAuthService(defaultResult: AuthFailure(reason, message: message));

  static final AuthUser _fakeUser =
      const AuthUser(id: 'local:fake@test', email: 'fake@test');
  static final AuthResult _defaultSuccess =
      AuthSuccess(AuthSession(user: _fakeUser, accessToken: 'fake-token'));

  @override
  Stream<AuthUser?> get authStateChanges async* {
    yield _currentUser;
    yield* _controller.stream;
  }

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  Future<AuthResult> signUp(EmailPasswordCredentials credentials) async {
    signUpCalls.add(credentials);
    return _next();
  }

  @override
  Future<AuthResult> signIn(EmailPasswordCredentials credentials) async {
    signInCalls.add(credentials);
    return _next();
  }

  @override
  Future<AuthResult> signInWithApple() async {
    appleCalls++;
    return _next();
  }

  @override
  Future<AuthResult> signInWithGoogle() async {
    googleCalls++;
    return _next();
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    emitUser(null);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _controller.close();
  }

  // --- Test controls -------------------------------------------------------

  /// Pushes an arbitrary auth state onto the stream (and updates
  /// [currentUser]). Pass `null` for signed out.
  void emitUser(AuthUser? user) {
    _currentUser = user;
    if (!_disposed) _controller.add(user);
  }

  /// Simulates token expiry: emits the signed-out state a real backend pushes
  /// when a session can no longer be refreshed. Pair with a scripted
  /// `AuthFailure(AuthFailureReason.tokenExpired)` on the next call to assert
  /// how a ViewModel routes an expired-session retry.
  void expireSession() => emitUser(null);

  /// Convenience for building a session that is already past its expiry — hand
  /// it to a scripted [AuthSuccess] to exercise `AuthSession.isExpiredAt`.
  static AuthSession expiredSession(
    AuthUser user, {
    Duration ago = const Duration(minutes: 1),
  }) =>
      AuthSession(
        user: user,
        accessToken: 'expired-token',
        expiresAt: DateTime.now().subtract(ago),
      );

  AuthResult _next() {
    final result = _cursor < scriptedResults.length
        ? scriptedResults[_cursor++]
        : defaultResult;
    if (result is AuthSuccess) emitUser(result.user);
    return result;
  }
}
