import '../../models/auth_result.dart';
import '../kit_oauth_provider.dart';

/// STUB — not implemented. Native Google sign-in.
///
/// TODO(phase-later): implement with `google_sign_in: ^7.2.0`. Note the v7
/// rewrite — it is NOT the pre-v7 API many guides still show. When wiring:
///   1. Add the dependency and configure the OAuth client ids per platform.
///   2. `await GoogleSignIn.instance.initialize(...)`, then
///      `GoogleSignIn.instance.authenticate()` (v7 replaced `signIn()`).
///   3. Take the `idToken` from the authorization, hand it to your backend's
///      token-exchange, and map onto [AuthResult] — a `GoogleSignInException`
///      with `code == canceled` ⇒ [AuthFailureReason.cancelled].
/// Do not import app code — this returns an [AuthResult] the caller composes.
class GoogleSignInProvider implements KitOAuthProvider {
  const GoogleSignInProvider();

  @override
  String get id => 'google';

  @override
  Future<AuthResult> signIn() =>
      throw UnimplementedError('GoogleSignInProvider.signIn (phase-later)');
}
