import 'appbox_kit_auth_types.dart';

/// The identity seam — one implementation per backend, selected by the same
/// `AppBoxKitDataConfig.backend` that picks the repositories. Auth deliberately
/// does NOT reuse `AppBoxKitRepository<T>`: session state has its own lifecycle.
///
/// The fake implementation pairs ONLY with the seed backend. Against a real
/// backend a fake session is a client-side fiction — Supabase RLS keys on
/// `auth.uid()` and Appwrite rows are default-deny — so smoke tests use
/// [signInAnonymously] or operator-seeded test users instead.
///
/// OTP is two-step by design: both real backends are (Supabase
/// `signInWithOtp` → `verifyOTP`; Appwrite `create*Token` → `createSession`),
/// so a one-shot method would misrepresent the flow the host must build UI
/// for.
abstract interface class AppBoxKitAuthService {
  /// Emits the current session immediately on listen, then on every change.
  /// `null` = signed out.
  Stream<AppBoxKitAuthSession?> get session$;

  AppBoxKitAuthSession? get currentSession;

  Future<AppBoxKitAuthSession> signUpWithEmailPassword({
    required String email,
    required String password,
  });

  Future<AppBoxKitAuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  });

  /// Exactly one of [email]/[phone] must be provided. Sends the code.
  Future<void> requestOtp({String? email, String? phone});

  /// Completes the OTP started by [requestOtp] for the same identity.
  Future<AppBoxKitAuthSession> confirmOtp({
    String? email,
    String? phone,
    required String code,
  });

  Future<AppBoxKitAuthSession> signInWithGoogle();

  Future<AppBoxKitAuthSession> signInWithApple();

  /// The smoke-test path on real backends: a real, server-issued session
  /// without user interaction. Both Supabase and Appwrite support it.
  Future<AppBoxKitAuthSession> signInAnonymously();

  Future<void> signOut();

  Future<void> dispose();
}
