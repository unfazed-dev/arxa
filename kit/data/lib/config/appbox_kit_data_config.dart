/// Configuration surface for the data layer.
///
/// A host app builds one [AppBoxKitDataConfig] and hands it to `AppBoxKitData.initialize`
/// in `main()`. The [backend] picks which repository implementation gets
/// registered — nothing else in the app changes when the backend changes.
library;

import 'appbox_kit_seed_profile.dart';

/// Which storage engine the app reads and writes through.
enum AppBoxKitDataBackend { seed, supabase, appwrite }

/// How the seed backend persists between launches.
enum AppBoxKitSeedPersistenceMode {
  /// Pure in-memory: every boot reloads fixtures. Reset-on-restart.
  none,

  /// Write-through JSON snapshot in the app-documents directory. Boot loads
  /// the snapshot when present, fixtures otherwise.
  snapshot,
}

class AppBoxKitSupabaseConfig {
  final String url;
  final String publishableKey;

  const AppBoxKitSupabaseConfig({required this.url, required this.publishableKey});
}

class AppBoxKitAppwriteConfig {
  final String endpoint;
  final String projectId;
  final String databaseId;

  const AppBoxKitAppwriteConfig({
    required this.endpoint,
    required this.projectId,
    required this.databaseId,
  });
}

/// Auth-seam configuration. Present ⇒ `AppBoxKitData.initialize` registers a
/// `AppBoxKitAuthService` for the selected backend; absent ⇒ no auth is wired.
class AppBoxKitAuthConfig {
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

  const AppBoxKitAuthConfig({
    this.googleServerClientId,
    this.googleClientId,
    this.fakeUsersAsset,
  });
}

class AppBoxKitDataConfig {
  /// Defaults to [AppBoxKitDataBackend.supabase] — the kit's default database.
  final AppBoxKitDataBackend backend;

  final AppBoxKitSupabaseConfig? supabase;
  final AppBoxKitAppwriteConfig? appwrite;

  /// Only meaningful when [backend] is [AppBoxKitDataBackend.seed].
  final AppBoxKitSeedPersistenceMode seedPersistence;

  /// Only meaningful when [backend] is [AppBoxKitDataBackend.seed]. The Seed
  /// Profile — latency/failure injection every seed repository applies so a
  /// host can force the slow / failing Read States (`null` = `normal`).
  final AppBoxKitSeedProfile? seedProfile;

  /// Wires the auth seam when present. See [AppBoxKitAuthConfig].
  final AppBoxKitAuthConfig? auth;

  /// Namespace UUID for deterministic canonical IDs (ADR-0001). Override only
  /// when two hosts must mint disjoint IDs from identical fixtures.
  final String? idNamespace;

  const AppBoxKitDataConfig({
    this.backend = AppBoxKitDataBackend.supabase,
    this.supabase,
    this.appwrite,
    this.seedPersistence = AppBoxKitSeedPersistenceMode.none,
    this.seedProfile,
    this.auth,
    this.idNamespace,
  });

  /// Throws [StateError] when the selected backend is missing its credentials.
  void validate() {
    switch (backend) {
      case AppBoxKitDataBackend.supabase:
        if (supabase == null) {
          throw StateError(
            'AppBoxKitDataConfig: backend is supabase but no AppBoxKitSupabaseConfig was provided.',
          );
        }
      case AppBoxKitDataBackend.appwrite:
        if (appwrite == null) {
          throw StateError(
            'AppBoxKitDataConfig: backend is appwrite but no AppBoxKitAppwriteConfig was provided.',
          );
        }
      case AppBoxKitDataBackend.seed:
        break;
    }
  }
}
