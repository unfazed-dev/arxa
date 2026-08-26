import '../models/arxa_kit_auth_credentials.dart';
import '../models/arxa_kit_auth_result.dart';
import '../models/arxa_kit_auth_user.dart';

/// The identity seam an app depends on. One implementation per backend
/// (in-memory default today; Seed / Supabase / native OAuth later), all behind
/// this port so ViewModels never import a backend SDK.
///
/// Failures are returned as [ArxaKitAuthFailure], not thrown — the only exceptions a
/// caller should expect are programming errors (e.g. using a disposed
/// service).
abstract interface class ArxaKitAuthService {
  /// Emits the current user immediately on listen, then on every change.
  /// `null` means signed out — which is also how token-expiry surfaces: an
  /// expired session emits `null`.
  Stream<ArxaKitAuthUser?> get authStateChanges;

  /// The signed-in user, or null. Synchronous snapshot of the stream's latest.
  ArxaKitAuthUser? get currentUser;

  /// Registers a new identity. Fails with [ArxaKitAuthFailureReason.emailAlreadyInUse]
  /// or [ArxaKitAuthFailureReason.weakPassword].
  Future<ArxaKitAuthResult> signUp(ArxaKitEmailPasswordCredentials credentials);

  /// Authenticates an existing identity. Fails with
  /// [ArxaKitAuthFailureReason.userNotFound] or [ArxaKitAuthFailureReason.invalidCredentials].
  Future<ArxaKitAuthResult> signIn(ArxaKitEmailPasswordCredentials credentials);

  /// Native Sign in with Apple. The in-memory default resolves a local
  /// identity; the real PassKit/OAuth flow is wired in a later phase.
  Future<ArxaKitAuthResult> signInWithApple();

  /// Native Google sign-in. The in-memory default resolves a local identity;
  /// the real google_sign_in flow is wired in a later phase.
  Future<ArxaKitAuthResult> signInWithGoogle();

  /// Ends the session and emits `null` on [authStateChanges].
  Future<void> signOut();

  /// Releases the stream controller. The service is unusable afterward.
  Future<void> dispose();
}
