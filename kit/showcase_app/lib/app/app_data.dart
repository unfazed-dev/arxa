import 'package:appbox_kit_data/appbox_kit_data.dart';

import 'package:appbox_kit_showcase_app/data/schemas/showcase_notes_schemas/showcase_note_schema.dart';
import 'package:appbox_kit_showcase_app/data/schemas/showcase_notes_schemas/showcase_note_folder_schema.dart';

/// The app's data-layer boot. Called once from `main()` after `setupLocator()`.
///
/// Boots `appbox_kit_data` with the Notes entities + fixtures. Service
/// registration (ShowcaseNotesFacadeService, ShowcaseNotesMediaAdapterService — like every other service)
/// lives in the `@StackedApp` dependencies (lib/app/app.dart), created via
/// `stacked create service …`; they're lazy singletons, so they construct on
/// first use — safely after this boot completes.
class AppData {
  AppData._();

  /// Asset key prefix. This package IS the app, so its own pubspec-declared
  /// assets bundle under plain keys — the `packages/<name>/` prefix only
  /// exists when another app depends on this one.
  static const _assets = 'data/seed';

  /// The bundled fake-users fixture, public so a custom [KitDataConfig] (or a
  /// test) can point [KitAuthConfig.fakeUsersAsset] at the same file.
  static const fakeUsersAsset = '$_assets/kit_auth_users.json';

  /// The bundled Notes fixtures, in load order.
  static const fixtureAssets = [
    '$_assets/notes_folders.json',
    '$_assets/notes.json',
  ];

  /// Boots the data layer. [config] defaults to the seed backend with
  /// write-through snapshot persistence and fake auth pre-seeded from the
  /// bundled users fixture — pass a supabase/appwrite config to smoke-test a
  /// real backend with zero other changes (that absence of change is the
  /// point). [assetReader] is a test seam, forwarded to `KitData.initialize`.
  static Future<void> initialize({
    KitDataConfig? config,
    KitAssetReader? assetReader,
  }) async {
    await KitData.initialize(
      config: config ??
          const KitDataConfig(
            backend: KitDataBackend.seed,
            seedPersistence: KitSeedPersistenceMode.snapshot,
            auth: KitAuthConfig(fakeUsersAsset: fakeUsersAsset),
          ),
      entities: [showcaseNoteFolderRegistration, showcaseNoteRegistration],
      fixtureAssets: fixtureAssets,
      assetReader: assetReader,
    );
  }
}
