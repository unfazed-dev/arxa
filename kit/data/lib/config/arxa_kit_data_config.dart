/// Configuration surface for the data layer.
///
/// A host app builds one [ArxaKitDataConfig] and hands it to `ArxaKitData.initialize`
/// in `main()`. The [backend] picks which repository implementation gets
/// registered — nothing else in the app changes when the backend changes.
library;

import 'arxa_kit_seed_profile.dart';

/// Which storage engine the app reads and writes through.
enum ArxaKitDataBackend { seed, supabase, appwrite }

/// How the seed backend persists between launches.
enum ArxaKitSeedPersistenceMode {
  /// Pure in-memory: every boot reloads fixtures. Reset-on-restart.
  none,

  /// Write-through JSON snapshot in the app-documents directory. Boot loads
  /// the snapshot when present, fixtures otherwise.
  snapshot,
}

class ArxaKitSupabaseConfig {
  final String url;
  final String publishableKey;

  const ArxaKitSupabaseConfig({required this.url, required this.publishableKey});
}

class ArxaKitAppwriteConfig {
  final String endpoint;
  final String projectId;
  final String databaseId;

  const ArxaKitAppwriteConfig({
    required this.endpoint,
    required this.projectId,
    required this.databaseId,
  });
}

/// Auth-seam configuration. Present ⇒ `ArxaKitData.initialize` registers a
/// `ArxaKitAuthService` for the selected backend; absent ⇒ no auth is wired.
class ArxaKitAuthConfig {
  /// Google OAuth *web/server* client ID — required for the Supabase native
  /// Google flow (google_sign_in v7 hands it the idToken audience). Ignored
  /// by seed and Appwrite (Appwrite's OAuth is configured server-side).
  final String? googleServerClientId;

  /// Platform client ID for google_sign_in on iOS/macOS, when it differs
  /// from the platform defaults picked up from the plist.
  final String? googleClientId;

  /// Optional fixture asset (`assets/seed/kit_auth_users.json`) pre-seeding
  /// fake users. Unknown identities are auto-created on sign-in regardless.
  final String? fakeUsersAsset;

  const ArxaKitAuthConfig({
    this.googleServerClientId,
    this.googleClientId,
    this.fakeUsersAsset,
  });
}

class ArxaKitDataConfig {
  /// Defaults to [ArxaKitDataBackend.supabase] — the kit's default database.
  final ArxaKitDataBackend backend;

  final ArxaKitSupabaseConfig? supabase;
  final ArxaKitAppwriteConfig? appwrite;

  /// Only meaningful when [backend] is [ArxaKitDataBackend.seed].
  final ArxaKitSeedPersistenceMode seedPersistence;

  /// Only meaningful when [backend] is [ArxaKitDataBackend.seed]. The Seed
  /// Profile — latency/failure injection every seed repository applies so a
  /// host can force the slow / failing Read States (`null` = `normal`).
  final ArxaKitSeedProfile? seedProfile;

  /// Wires the auth seam when present. See [ArxaKitAuthConfig].
  final ArxaKitAuthConfig? auth;

  /// Namespace UUID for deterministic canonical IDs (ADR-0001). Override only
  /// when two hosts must mint disjoint IDs from identical fixtures.
  final String? idNamespace;

  const ArxaKitDataConfig({
    this.backend = ArxaKitDataBackend.supabase,
    this.supabase,
    this.appwrite,
    this.seedPersistence = ArxaKitSeedPersistenceMode.none,
    this.seedProfile,
    this.auth,
    this.idNamespace,
  });

  /// Throws [StateError] when the selected backend is missing its credentials.
  void validate() {
    switch (backend) {
      case ArxaKitDataBackend.supabase:
        if (supabase == null) {
          throw StateError(
            'ArxaKitDataConfig: backend is supabase but no ArxaKitSupabaseConfig was provided.',
          );
        }
      case ArxaKitDataBackend.appwrite:
        if (appwrite == null) {
          throw StateError(
            'ArxaKitDataConfig: backend is appwrite but no ArxaKitAppwriteConfig was provided.',
          );
        }
      case ArxaKitDataBackend.seed:
        break;
    }
  }
}
