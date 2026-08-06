import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../models/appbox_kit_auth_failure.dart';
import '../../models/appbox_kit_auth_result.dart';
import '../../models/appbox_kit_auth_session.dart';
import '../../models/appbox_kit_auth_user.dart';
import '../appbox_kit_oauth_provider.dart';

/// The plugin's credential call, injectable so unit tests can substitute the
/// platform channel boundary.
typedef AppBoxKitAppleCredentialFetcher = Future<AuthorizationCredentialAppleID>
    Function({
  required List<AppleIDAuthorizationScopes> scopes,
  String? nonce,
  WebAuthenticationOptions? webAuthenticationOptions,
});

/// Native Sign in with Apple, via the `sign_in_with_apple` plugin.
///
/// Flow: capability probe → fresh raw nonce (SHA-256 hashed into the request)
/// → `SignInWithApple.getAppleIDCredential` with the email + fullName scopes.
///
/// Result mapping (the token handoff a backend consumes):
/// - `session.accessToken` — the Apple `identityToken` JWT. Verify it
///   server-side against Apple's JWKS (https://appleid.apple.com/auth/keys)
///   with iss/aud/exp checks; its `sub` equals `user.id`.
/// - `session.refreshToken` — the single-use `authorizationCode`, for the
///   backend's token exchange.
/// - `user.metadata['rawNonce']` — the raw nonce whose SHA-256 hash was sent;
///   the backend checks it against the JWT's `nonce` claim.
///
/// Apple only returns `email` / `givenName` / `familyName` on the FIRST
/// authorization for an app — later sign-ins carry only `userIdentifier`
/// (and the tokens), so a null email/name here is normal, not an error.
/// Persist them at first auth.
///
/// Cancellation maps to [AppBoxKitAuthFailureReason.cancelled]; a failed capability
/// probe or an unsupported device maps to
/// [AppBoxKitAuthFailureReason.operationNotAllowed] (Apple rejects apps whose
/// Apple-sign-in button silently no-ops).
class AppBoxKitAppleSignInProvider implements AppBoxKitOAuthProvider {
  /// The OAuth scopes requested from Apple.
  final List<AppleIDAuthorizationScopes> scopes;

  /// Required on Android/web (web-service flow); ignored on iOS/macOS.
  final WebAuthenticationOptions? webAuthenticationOptions;

  final Future<bool> Function() _isAvailable;
  final AppBoxKitAppleCredentialFetcher _getCredential;
  final String Function() _rawNonce;

  AppBoxKitAppleSignInProvider({
    this.scopes = const [
      AppleIDAuthorizationScopes.email,
      AppleIDAuthorizationScopes.fullName,
    ],
    this.webAuthenticationOptions,
    Future<bool> Function()? isAvailable,
    AppBoxKitAppleCredentialFetcher? getCredential,
    String Function()? rawNonce,
  })  : _isAvailable = isAvailable ?? SignInWithApple.isAvailable,
        _getCredential = getCredential ?? SignInWithApple.getAppleIDCredential,
        _rawNonce = rawNonce ?? _generateNonce;

  @override
  String get id => 'apple';

  @override
  Future<AppBoxKitAuthResult> signIn() async {
    if (!await _isAvailable()) {
      return const AppBoxKitAuthFailure(
        AppBoxKitAuthFailureReason.operationNotAllowed,
        message: 'Sign in with Apple is not available on this device',
      );
    }
    final rawNonce = _rawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final AuthorizationCredentialAppleID credential;
    try {
      credential = await _getCredential(
        scopes: scopes,
        nonce: hashedNonce,
        webAuthenticationOptions: webAuthenticationOptions,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return AppBoxKitAuthFailure(
          AppBoxKitAuthFailureReason.cancelled,
          message: e.message,
          cause: e,
        );
      }
      return AppBoxKitAuthFailure(
        AppBoxKitAuthFailureReason.unknown,
        message: e.message,
        cause: e,
      );
    } on SignInWithAppleNotSupportedException catch (e) {
      return AppBoxKitAuthFailure(
        AppBoxKitAuthFailureReason.operationNotAllowed,
        message: e.message,
        cause: e,
      );
    } on SignInWithAppleException catch (e) {
      return AppBoxKitAuthFailure(AppBoxKitAuthFailureReason.unknown, cause: e);
    }

    final name = [credential.givenName, credential.familyName]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' ');
    final user = AppBoxKitAuthUser(
      id: credential.userIdentifier ?? credential.email ?? 'apple-user',
      email: credential.email,
      displayName: name.isEmpty ? null : name,
      metadata: {'provider': 'apple', 'rawNonce': rawNonce},
    );
    return AppBoxKitAuthSuccess(AppBoxKitAuthSession(
      user: user,
      accessToken: credential.identityToken,
      refreshToken: credential.authorizationCode,
    ));
  }

  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return [
      for (var i = 0; i < length; i++) charset[random.nextInt(charset.length)],
    ].join();
  }
}
