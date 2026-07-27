import 'package:stacked_kit_data/stacked_kit_data.dart';

/// The app's data-layer boot. Called once from `main()` after `setupLocator()`.
///
/// Boots `stacked_kit_data` with the seed backend + fake auth. The
/// Repository → Facade → ViewModel layering is the pattern this base carries;
/// app_box's own domain entities are registered in a later step.
///
/// Service registration lives in the `@StackedApp` dependencies
/// (lib/app/app.dart) — lazy singletons, so they construct on first use,
/// safely after this boot completes.
class AppData {
  AppData._();

  /// Asset key prefix. This package IS the app, so its own pubspec-declared
  /// assets bundle under plain keys — the `packages/<name>/` prefix only
  /// exists when another app depends on this one.
  static const _assets = 'assets/seed';

  /// The bundled fake-users fixture, public so a custom [KitDataConfig] (or a
  /// test) can point [KitAuthConfig.fakeUsersAsset] at the same file.
  static const fakeUsersAsset = '$_assets/kit_auth_users.json';

  /// The bundled domain fixtures, in load order. None yet — app_box's domain
  /// entities are added in a later step.
  static const fixtureAssets = <String>[];

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
      entities: const [],
      fixtureAssets: fixtureAssets,
      assetReader: assetReader,
    );
  }
}
