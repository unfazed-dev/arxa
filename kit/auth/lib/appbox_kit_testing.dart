/// Scriptable fake for `appbox_kit_auth`. Import ONLY from tests / storybook:
///
/// ```dart
/// import 'package:appbox_kit_auth/appbox_kit_testing.dart';
/// ```
library;

import 'dart:async';

import 'src/models/appbox_kit_auth_credentials.dart';
import 'src/models/appbox_kit_auth_failure.dart';
import 'src/models/appbox_kit_auth_result.dart';
import 'src/models/appbox_kit_auth_session.dart';
import 'src/models/appbox_kit_auth_user.dart';
import 'src/service/appbox_kit_auth_service.dart';

export 'src/models/appbox_kit_auth_credentials.dart';
export 'src/models/appbox_kit_auth_failure.dart';
export 'src/models/appbox_kit_auth_result.dart';
export 'src/models/appbox_kit_auth_session.dart';
export 'src/models/appbox_kit_auth_user.dart';

/// A [AppBoxKitAuthService] whose outcomes and state transitions you drive.
///
/// Each auth method returns the next entry of [scriptedResults] (falling back
/// to [defaultResult]); an [AppBoxKitAuthSuccess] also pushes its user onto
/// [authStateChanges]. Beyond scripting, the control methods let a test drive
/// the stream directly — including [expireSession], which emits the signed-out
/// state a token expiry produces at runtime.
class FakeAppBoxKitAuthService implements AppBoxKitAuthService {
  /// Results handed out by the auth methods, in order.
  final List<AppBoxKitAuthResult> scriptedResults;

  /// Returned once [scriptedResults] is exhausted.
  final AppBoxKitAuthResult defaultResult;

  final StreamController<AppBoxKitAuthUser?> _controller =
      StreamController<AppBoxKitAuthUser?>.broadcast();
  AppBoxKitAuthUser? _currentUser;
  int _cursor = 0;
  bool _disposed = false;

  // Call records for assertions.
  final List<AppBoxKitEmailPasswordCredentials> signUpCalls = [];
  final List<AppBoxKitEmailPasswordCredentials> signInCalls = [];
  int appleCalls = 0;
  int googleCalls = 0;
  int signOutCalls = 0;

  FakeAppBoxKitAuthService({
    AppBoxKitAuthUser? initialUser,
    List<AppBoxKitAuthResult>? scriptedResults,
    AppBoxKitAuthResult? defaultResult,
  })  : scriptedResults = scriptedResults ?? const [],
        defaultResult = defaultResult ?? _defaultSuccess,
        _currentUser = initialUser;

  /// Starts signed in as [user]; every method succeeds with a session for it.
  factory FakeAppBoxKitAuthService.signedIn(AppBoxKitAuthUser user) => FakeAppBoxKitAuthService(
        initialUser: user,
        defaultResult: AppBoxKitAuthSuccess(AppBoxKitAuthSession(user: user)),
      );

  /// Starts signed out; every method succeeds with a synthetic user.
  factory FakeAppBoxKitAuthService.signedOut() => FakeAppBoxKitAuthService();

  /// Every method fails with [reason].
  factory FakeAppBoxKitAuthService.alwaysFails(
    AppBoxKitAuthFailureReason reason, {
    String message = 'fake failure',
  }) =>
      FakeAppBoxKitAuthService(defaultResult: AppBoxKitAuthFailure(reason, message: message));

  static final AppBoxKitAuthUser _fakeUser =
      const AppBoxKitAuthUser(id: 'local:fake@test', email: 'fake@test');
  static final AppBoxKitAuthResult _defaultSuccess =
      AppBoxKitAuthSuccess(AppBoxKitAuthSession(user: _fakeUser, accessToken: 'fake-token'));

  @override
  Stream<AppBoxKitAuthUser?> get authStateChanges async* {
    yield _currentUser;
    yield* _controller.stream;
  }

  @override
  AppBoxKitAuthUser? get currentUser => _currentUser;

  @override
  Future<AppBoxKitAuthResult> signUp(AppBoxKitEmailPasswordCredentials credentials) async {
    signUpCalls.add(credentials);
    return _next();
  }

  @override
  Future<AppBoxKitAuthResult> signIn(AppBoxKitEmailPasswordCredentials credentials) async {
    signInCalls.add(credentials);
    return _next();
  }

  @override
  Future<AppBoxKitAuthResult> signInWithApple() async {
    appleCalls++;
    return _next();
  }

  @override
  Future<AppBoxKitAuthResult> signInWithGoogle() async {
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
  void emitUser(AppBoxKitAuthUser? user) {
    _currentUser = user;
    if (!_disposed) _controller.add(user);
  }

  /// Simulates token expiry: emits the signed-out state a real backend pushes
  /// when a session can no longer be refreshed. Pair with a scripted
  /// `AppBoxKitAuthFailure(AppBoxKitAuthFailureReason.tokenExpired)` on the next call to assert
  /// how a ViewModel routes an expired-session retry.
  void expireSession() => emitUser(null);

  /// Convenience for building a session that is already past its expiry — hand
  /// it to a scripted [AppBoxKitAuthSuccess] to exercise `AppBoxKitAuthSession.isExpiredAt`.
  static AppBoxKitAuthSession expiredSession(
    AppBoxKitAuthUser user, {
    Duration ago = const Duration(minutes: 1),
  }) =>
      AppBoxKitAuthSession(
        user: user,
        accessToken: 'expired-token',
        expiresAt: DateTime.now().subtract(ago),
      );

  AppBoxKitAuthResult _next() {
    final result = _cursor < scriptedResults.length
        ? scriptedResults[_cursor++]
        : defaultResult;
    if (result is AppBoxKitAuthSuccess) emitUser(result.user);
    return result;
  }
}
