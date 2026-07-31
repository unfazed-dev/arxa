import '../models/auth_result.dart';

/// A single native OAuth flow (Apple, Google, …), factored out of
/// [KitAuthService] so the interactive part can be swapped/stubbed
/// independently of the identity store it feeds.
///
/// The in-memory default does not use these (it mints local identities);
/// they exist so a real backend can compose `provider.signIn()` with its own
/// token-exchange step.
abstract interface class KitOAuthProvider {
  /// Stable id, e.g. `'apple'` / `'google'`.
  String get id;

  /// Runs the interactive flow and returns an [AuthResult]. User back-out maps
  /// to an [AuthFailure] with [AuthFailureReason.cancelled], not an exception.
  Future<AuthResult> signIn();
}
