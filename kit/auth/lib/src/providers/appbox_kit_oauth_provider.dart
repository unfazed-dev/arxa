import '../models/appbox_kit_auth_result.dart';

/// A single native OAuth flow (Apple, Google, …), factored out of
/// [AppBoxKitAuthService] so the interactive part can be swapped/stubbed
/// independently of the identity store it feeds.
///
/// The in-memory default does not use these (it mints local identities);
/// they exist so a real backend can compose `provider.signIn()` with its own
/// token-exchange step.
abstract interface class AppBoxKitOAuthProvider {
  /// Stable id, e.g. `'apple'` / `'google'`.
  String get id;

  /// Runs the interactive flow and returns an [AppBoxKitAuthResult]. User back-out maps
  /// to an [AppBoxKitAuthFailure] with [AppBoxKitAuthFailureReason.cancelled], not an exception.
  Future<AppBoxKitAuthResult> signIn();
}
