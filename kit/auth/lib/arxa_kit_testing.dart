/// Scriptable fake for `arxa_kit_auth`. Import ONLY from tests / storybook:
///
/// ```dart
/// import 'package:arxa_kit_auth/arxa_kit_testing.dart';
/// ```
library;

import 'dart:async';

import 'src/models/arxa_kit_auth_credentials.dart';
import 'src/models/arxa_kit_auth_failure.dart';
import 'src/models/arxa_kit_auth_result.dart';
import 'src/models/arxa_kit_auth_session.dart';
import 'src/models/arxa_kit_auth_user.dart';
import 'src/service/arxa_kit_auth_service.dart';

export 'src/models/arxa_kit_auth_credentials.dart';
export 'src/models/arxa_kit_auth_failure.dart';
export 'src/models/arxa_kit_auth_result.dart';
export 'src/models/arxa_kit_auth_session.dart';
export 'src/models/arxa_kit_auth_user.dart';

/// A [ArxaKitAuthService] whose outcomes and state transitions you drive.
///
/// Each auth method returns the next entry of [scriptedResults] (falling back
/// to [defaultResult]); an [ArxaKitAuthSuccess] also pushes its user onto
/// [authStateChanges]. Beyond scripting, the control methods let a test drive
/// the stream directly — including [expireSession], which emits the signed-out
/// state a token expiry produces at runtime.
class FakeArxaKitAuthService implements ArxaKitAuthService {
  /// Results handed out by the auth methods, in order.
  final List<ArxaKitAuthResult> scriptedResults;

  /// Returned once [scriptedResults] is exhausted.
  final ArxaKitAuthResult defaultResult;

  final StreamController<ArxaKitAuthUser?> _controller =
      StreamController<ArxaKitAuthUser?>.broadcast();
  ArxaKitAuthUser? _currentUser;
  int _cursor = 0;
  bool _disposed = false;

  // Call records for assertions.
  final List<ArxaKitEmailPasswordCredentials> signUpCalls = [];
  final List<ArxaKitEmailPasswordCredentials> signInCalls = [];
  int appleCalls = 0;
  int googleCalls = 0;
  int signOutCalls = 0;

  FakeArxaKitAuthService({
    ArxaKitAuthUser? initialUser,
    List<ArxaKitAuthResult>? scriptedResults,
    ArxaKitAuthResult? defaultResult,
  })  : scriptedResults = scriptedResults ?? const [],
        defaultResult = defaultResult ?? _defaultSuccess,
        _currentUser = initialUser;

  /// Starts signed in as [user]; every method succeeds with a session for it.
  factory FakeArxaKitAuthService.signedIn(ArxaKitAuthUser user) => FakeArxaKitAuthService(
        initialUser: user,
        defaultResult: ArxaKitAuthSuccess(ArxaKitAuthSession(user: user)),
      );

  /// Starts signed out; every method succeeds with a synthetic user.
  factory FakeArxaKitAuthService.signedOut() => FakeArxaKitAuthService();

  /// Every method fails with [reason].
  factory FakeArxaKitAuthService.alwaysFails(
    ArxaKitAuthFailureReason reason, {
    String message = 'fake failure',
  }) =>
      FakeArxaKitAuthService(defaultResult: ArxaKitAuthFailure(reason, message: message));

  static final ArxaKitAuthUser _fakeUser =
      const ArxaKitAuthUser(id: 'local:fake@test', email: 'fake@test');
  static final ArxaKitAuthResult _defaultSuccess =
      ArxaKitAuthSuccess(ArxaKitAuthSession(user: _fakeUser, accessToken: 'fake-token'));

  @override
  Stream<ArxaKitAuthUser?> get authStateChanges async* {
    yield _currentUser;
    yield* _controller.stream;
  }

  @override
  ArxaKitAuthUser? get currentUser => _currentUser;

  @override
  Future<ArxaKitAuthResult> signUp(ArxaKitEmailPasswordCredentials credentials) async {
    signUpCalls.add(credentials);
    return _next();
  }

  @override
  Future<ArxaKitAuthResult> signIn(ArxaKitEmailPasswordCredentials credentials) async {
    signInCalls.add(credentials);
    return _next();
  }

  @override
  Future<ArxaKitAuthResult> signInWithApple() async {
    appleCalls++;
    return _next();
  }

  @override
  Future<ArxaKitAuthResult> signInWithGoogle() async {
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
  void emitUser(ArxaKitAuthUser? user) {
    _currentUser = user;
    if (!_disposed) _controller.add(user);
  }

  /// Simulates token expiry: emits the signed-out state a real backend pushes
  /// when a session can no longer be refreshed. Pair with a scripted
  /// `ArxaKitAuthFailure(ArxaKitAuthFailureReason.tokenExpired)` on the next call to assert
  /// how a ViewModel routes an expired-session retry.
  void expireSession() => emitUser(null);

  /// Convenience for building a session that is already past its expiry — hand
  /// it to a scripted [ArxaKitAuthSuccess] to exercise `ArxaKitAuthSession.isExpiredAt`.
  static ArxaKitAuthSession expiredSession(
    ArxaKitAuthUser user, {
    Duration ago = const Duration(minutes: 1),
  }) =>
      ArxaKitAuthSession(
        user: user,
        accessToken: 'expired-token',
        expiresAt: DateTime.now().subtract(ago),
      );

  ArxaKitAuthResult _next() {
    final result = _cursor < scriptedResults.length
        ? scriptedResults[_cursor++]
        : defaultResult;
    if (result is ArxaKitAuthSuccess) emitUser(result.user);
    return result;
  }
}
