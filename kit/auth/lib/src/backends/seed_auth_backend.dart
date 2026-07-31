import '../models/auth_credentials.dart';
import '../models/auth_result.dart';
import '../models/auth_user.dart';
import '../service/kit_auth_service.dart';

/// STUB — not implemented. The seam where this package meets the host app's
/// existing **Seed** auth backend.
///
/// TODO(phase-4): implement by delegating to the app's Seed auth service.
/// Keep this a clean interface seam — DO NOT import app code into this
/// package. Instead, the host constructs its Seed service and passes the few
/// operations this needs in via the constructor (a set of function refs or a
/// tiny host-defined port), so `appbox_kit_auth` stays dependency-free of the
/// application. When wiring:
///   1. Define the minimal set of Seed operations needed (resolve identity,
///      issue/refresh session, revoke) as constructor parameters.
///   2. Map Seed's errors onto [AuthFailureReason] — expired seed session ⇒
///      [AuthFailureReason.tokenExpired].
///   3. Bridge Seed's identity change signal to [authStateChanges].
class SeedAuthBackend implements KitAuthService {
  const SeedAuthBackend();

  @override
  Stream<AuthUser?> get authStateChanges =>
      throw UnimplementedError('SeedAuthBackend is a stub (phase-4)');

  @override
  AuthUser? get currentUser =>
      throw UnimplementedError('SeedAuthBackend is a stub (phase-4)');

  @override
  Future<AuthResult> signUp(EmailPasswordCredentials credentials) =>
      throw UnimplementedError('SeedAuthBackend.signUp (phase-4)');

  @override
  Future<AuthResult> signIn(EmailPasswordCredentials credentials) =>
      throw UnimplementedError('SeedAuthBackend.signIn (phase-4)');

  @override
  Future<AuthResult> signInWithApple() =>
      throw UnimplementedError('SeedAuthBackend.signInWithApple (phase-4)');

  @override
  Future<AuthResult> signInWithGoogle() =>
      throw UnimplementedError('SeedAuthBackend.signInWithGoogle (phase-4)');

  @override
  Future<void> signOut() =>
      throw UnimplementedError('SeedAuthBackend.signOut (phase-4)');

  @override
  Future<void> dispose() =>
      throw UnimplementedError('SeedAuthBackend.dispose (phase-4)');
}
