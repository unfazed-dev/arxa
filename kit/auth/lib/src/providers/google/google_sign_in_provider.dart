import 'package:google_sign_in/google_sign_in.dart';

import '../../models/auth_failure.dart';
import '../../models/auth_result.dart';
import '../../models/auth_session.dart';
import '../../models/auth_user.dart';
import '../kit_oauth_provider.dart';

/// Native Google sign-in, via the `google_sign_in` v7 plugin. NOTE: v7 is a
/// breaking rewrite of the pre-v7 API many guides still show — it is
/// `GoogleSignIn.instance` + `initialize()` + `authenticate()`, NOT
/// `GoogleSignIn()` + `signIn()`.
///
/// Required configuration per platform:
/// - **iOS**: `GIDClientID` in Info.plist plus the reversed client id as a
///   URL scheme (both from GoogleService-Info.plist), or pass [clientId]
///   (the iOS OAuth client id) explicitly.
/// - **Android**: [serverClientId] — the *web* OAuth client id from the same
///   Google Cloud project — is effectively required: without it Android
///   cannot mint an `idToken`. The Android app also needs its SHA-1
///   fingerprint registered in the project.
/// - **Web**: [clientId] is required (the web OAuth client id).
///
/// Flow: `initialize(clientId:, serverClientId:)` → `supportsAuthenticate()`
/// probe → `authenticate()`. Authorization (access tokens for Google APIs)
/// is a separate step on purpose — this provider only authenticates; if a
/// caller needs scopes it should use the returned account's
/// `authorizationClient` itself.
///
/// Result mapping: `session.accessToken` is the Google `idToken` JWT — hand
/// it to the backend, which verifies it against Google's certs with
/// iss/aud/exp checks (`sub` equals `user.id`). A user back-out throws a
/// [GoogleSignInException] with `code == canceled`, mapped to
/// [AuthFailureReason.cancelled]; configuration problems map to
/// [AuthFailureReason.operationNotAllowed].
class GoogleSignInProvider implements KitOAuthProvider {
  /// Platform OAuth client id (iOS / web). See the class doc.
  final String? clientId;

  /// Web OAuth client id — effectively required on Android to get an
  /// `idToken`. See the class doc.
  final String? serverClientId;

  /// Scopes the caller intends to authorize right after authenticating;
  /// forwarded as a hint to platforms that support a combined flow.
  final List<String> scopeHint;

  final GoogleSignIn _googleSignIn;

  GoogleSignInProvider({
    this.clientId,
    this.serverClientId,
    this.scopeHint = const [],
    GoogleSignIn? googleSignIn,
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  @override
  String get id => 'google';

  @override
  Future<AuthResult> signIn() async {
    try {
      await _googleSignIn.initialize(
        clientId: clientId,
        serverClientId: serverClientId,
      );
      if (!_googleSignIn.supportsAuthenticate()) {
        return const AuthFailure(
          AuthFailureReason.operationNotAllowed,
          message:
              'This platform does not support authenticate() — use its '
              'platform-controlled sign-in UI instead',
        );
      }
      final account = await _googleSignIn.authenticate(scopeHint: scopeHint);
      final user = AuthUser(
        id: account.id,
        email: account.email,
        displayName: account.displayName,
        metadata: {
          'provider': 'google',
          if (account.photoUrl != null) 'photoUrl': account.photoUrl!,
        },
      );
      return AuthSuccess(AuthSession(
        user: user,
        accessToken: account.authentication.idToken,
      ));
    } on GoogleSignInException catch (e) {
      return switch (e.code) {
        GoogleSignInExceptionCode.canceled => AuthFailure(
            AuthFailureReason.cancelled,
            message: e.description ?? 'Sign-in cancelled',
            cause: e,
          ),
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          AuthFailure(
            AuthFailureReason.operationNotAllowed,
            message: e.description ?? 'Google sign-in is misconfigured',
            cause: e,
          ),
        _ => AuthFailure(
            AuthFailureReason.unknown,
            message: e.description ?? 'Google sign-in failed',
            cause: e,
          ),
      };
    }
  }
}
