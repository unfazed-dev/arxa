/// Identity types shared by every [AppBoxKitAuthService] implementation.
library;

/// The reserved users table every backend canonicalizes identity keys
/// against. On the seed backend it's a real `AppBoxKitSeedStore` table (never
/// emitted, never pushed by the seeder, snapshot-persisted); on real
/// backends it exists only as the id namespace, so the same identity key
/// resolves to the same canonical ID everywhere.
const String kAppBoxKitAuthUsersTable = 'kit_auth_users';

/// The signed-in identity. [id] is always a canonical ID (ADR-0001) — a real
/// backend uid passes through untouched; a fake user's seed key is minted
/// deterministically, so fixture rows referencing users line up with the
/// session on the seed backend.
class AppBoxKitAuthUser {
  final String id;
  final String? email;
  final String? phone;
  final String? displayName;
  final bool isAnonymous;
  final Map<String, dynamic> metadata;

  const AppBoxKitAuthUser({
    required this.id,
    this.email,
    this.phone,
    this.displayName,
    this.isAnonymous = false,
    this.metadata = const {},
  });
}

/// A live session. Token fields are null on the seed backend — nothing
/// outside the auth seam should ever need them; they exist for hosts that
/// must hand a JWT to something the kit doesn't wrap.
class AppBoxKitAuthSession {
  final AppBoxKitAuthUser user;
  final String? accessToken;
  final DateTime? expiresAt;

  const AppBoxKitAuthSession({
    required this.user,
    this.accessToken,
    this.expiresAt,
  });
}

/// Uniform failure surface: every implementation wraps its SDK's exception
/// (kept in [cause]) so callers never import backend SDKs to catch errors.
class AppBoxKitAuthException implements Exception {
  final String message;
  final String? code;
  final Object? cause;

  const AppBoxKitAuthException(this.message, {this.code, this.cause});

  @override
  String toString() =>
      'AppBoxKitAuthException(${code == null ? '' : '$code: '}$message)';
}
