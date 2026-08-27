import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';

import 'package:arxa_kit_showcase_app/data/schemas/showcase_notes_schemas/showcase_note_schema.dart';
import 'package:arxa_kit_showcase_app/data/schemas/showcase_notes_schemas/showcase_note_folder_schema.dart';

/// The app's data-layer boot. Called once from `main()` after `setupLocator()`.
///
/// Boots `arxa_kit_data` with the Notes entities + fixtures. Service
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

  /// The bundled fake-users fixture, public so a custom [ArxaKitDataConfig] (or a
  /// test) can point [ArxaKitAuthConfig.fakeUsersAsset] at the same file.
  static const fakeUsersAsset = '$_assets/kit_auth_users.json';

  /// The bundled Notes fixtures, in load order.
  static const fixtureAssets = [
    '$_assets/notes_folders.json',
    '$_assets/notes.json',
  ];

  /// The default boot config: the seed backend, UNLESS the
  /// `ARXA_CAIRN_MODE` dart-define is set — then the cairn plugin takes over
  /// (config from the `ARXA_CAIRN_*` define surface) and NOTHING else in the
  /// app changes. That absence of change is the point of the seam:
  ///
  /// ```sh
  /// flutter run --dart-define=ARXA_CAIRN_MODE=local
  /// ```
  ///
  /// Note: with the plugin backend the bundled fixtures are not (yet) seeded
  /// and auth is app-side in localOnly/sync — the cairn boot starts empty.
  static ArxaKitDataConfig defaultConfig() {
    const cairnMode = String.fromEnvironment('ARXA_CAIRN_MODE');
    if (cairnMode.isNotEmpty) {
      return ArxaKitDataConfig(
        backend: ArxaKitDataBackend.plugin,
        plugin: ArxaKitCairnBackend(
          config: ArxaKitCairnConfig.fromEnvironment(),
        ),
      );
    }
    return const ArxaKitDataConfig(
      backend: ArxaKitDataBackend.seed,
      seedPersistence: ArxaKitSeedPersistenceMode.snapshot,
      auth: ArxaKitAuthConfig(fakeUsersAsset: fakeUsersAsset),
    );
  }

  /// Boots the data layer. [config] defaults to [defaultConfig] — pass a
  /// supabase/appwrite/cairn config to smoke-test a real backend with zero
  /// other changes (that absence of change is the point). [assetReader] is a
  /// test seam, forwarded to `ArxaKitData.initialize`.
  static Future<void> initialize({
    ArxaKitDataConfig? config,
    ArxaKitAssetReader? assetReader,
  }) async {
    await ArxaKitData.initialize(
      config: config ?? defaultConfig(),
      entities: [showcaseNoteFolderRegistration, showcaseNoteRegistration],
      fixtureAssets: fixtureAssets,
      assetReader: assetReader,
    );
  }
}
