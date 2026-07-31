/// Configuration surface for the data layer.
///
/// A host app builds one [KitDataConfig] and hands it to `KitData.initialize`
/// in `main()`. The [backend] picks which repository implementation gets
/// registered — nothing else in the app changes when the backend changes.
library;

import 'kit_seed_profile.dart';

/// Which storage engine the app reads and writes through.
enum KitDataBackend { seed, supabase, appwrite }

/// How the seed backend persists between launches.
enum KitSeedPersistenceMode {
  /// Pure in-memory: every boot reloads fixtures. Reset-on-restart.
  none,

  /// Write-through JSON snapshot in the app-documents directory. Boot loads
  /// the snapshot when present, fixtures otherwise.
  snapshot,
}

class KitSupabaseConfig {
  final String url;
  final String publishableKey;

  const KitSupabaseConfig({required this.url, required this.publishableKey});
}

class KitAppwriteConfig {
  final String endpoint;
  final String projectId;
  final String databaseId;

  const KitAppwriteConfig({
    required this.endpoint,
    required this.projectId,
    required this.databaseId,
  });
}

/// Auth-seam configuration. Present ⇒ `KitData.initialize` registers a
/// `KitAuthService` for the selected backend; absent ⇒ no auth is wired.
class KitAuthConfig {
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

  const KitAuthConfig({
    this.googleServerClientId,
    this.googleClientId,
    this.fakeUsersAsset,
  });
}

class KitDataConfig {
  /// Defaults to [KitDataBackend.supabase] — the kit's default database.
  final KitDataBackend backend;

  final KitSupabaseConfig? supabase;
  final KitAppwriteConfig? appwrite;

  /// Only meaningful when [backend] is [KitDataBackend.seed].
  final KitSeedPersistenceMode seedPersistence;

  /// Only meaningful when [backend] is [KitDataBackend.seed]. The Seed
  /// Profile — latency/failure injection every seed repository applies so a
  /// host can force the slow / failing Read States (`null` = `normal`).
  final KitSeedProfile? seedProfile;

  /// Wires the auth seam when present. See [KitAuthConfig].
  final KitAuthConfig? auth;

  /// Namespace UUID for deterministic canonical IDs (ADR-0001). Override only
  /// when two hosts must mint disjoint IDs from identical fixtures.
  final String? idNamespace;

  const KitDataConfig({
    this.backend = KitDataBackend.supabase,
    this.supabase,
    this.appwrite,
    this.seedPersistence = KitSeedPersistenceMode.none,
    this.seedProfile,
    this.auth,
    this.idNamespace,
  });

  /// Throws [StateError] when the selected backend is missing its credentials.
  void validate() {
    switch (backend) {
      case KitDataBackend.supabase:
        if (supabase == null) {
          throw StateError(
            'KitDataConfig: backend is supabase but no KitSupabaseConfig was provided.',
          );
        }
      case KitDataBackend.appwrite:
        if (appwrite == null) {
          throw StateError(
            'KitDataConfig: backend is appwrite but no KitAppwriteConfig was provided.',
          );
        }
      case KitDataBackend.seed:
        break;
    }
  }
}
