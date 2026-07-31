import '../../models/auth_result.dart';
import '../kit_oauth_provider.dart';

/// STUB — not implemented. Native Sign in with Apple.
///
/// TODO(phase-later): implement with `sign_in_with_apple: ^8.1.0`. When wiring:
///   1. Add the dependency (and the "Sign In with Apple" capability on iOS).
///   2. Generate a raw nonce, SHA-256 it, and pass the hash to
///      `SignInWithApple.getAppleIDCredential(scopes: [...], nonce: hashed)`.
///   3. Hand the returned `identityToken` + raw nonce to your backend's
///      token-exchange, then map the result onto [AuthResult]
///      (`SignInWithAppleAuthorizationException(code: canceled)` ⇒
///      [AuthFailureReason.cancelled]).
/// Do not import app code — this returns an [AuthResult] the caller composes.
class AppleSignInProvider implements KitOAuthProvider {
  const AppleSignInProvider();

  @override
  String get id => 'apple';

  @override
  Future<AuthResult> signIn() =>
      throw UnimplementedError('AppleSignInProvider.signIn (phase-later)');
}
