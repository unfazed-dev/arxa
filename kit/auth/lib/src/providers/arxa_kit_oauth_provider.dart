import '../models/arxa_kit_auth_result.dart';

/// A single native OAuth flow (Apple, Google, …), factored out of
/// [ArxaKitAuthService] so the interactive part can be swapped/stubbed
/// independently of the identity store it feeds.
///
/// The in-memory default does not use these (it mints local identities);
/// they exist so a real backend can compose `provider.signIn()` with its own
/// token-exchange step.
abstract interface class ArxaKitOAuthProvider {
  /// Stable id, e.g. `'apple'` / `'google'`.
  String get id;

  /// Runs the interactive flow and returns an [ArxaKitAuthResult]. User back-out maps
  /// to an [ArxaKitAuthFailure] with [ArxaKitAuthFailureReason.cancelled], not an exception.
  Future<ArxaKitAuthResult> signIn();
}
