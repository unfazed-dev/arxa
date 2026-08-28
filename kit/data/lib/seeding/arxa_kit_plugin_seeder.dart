import '../assets/arxa_kit_asset_reader.dart';

/// Optional capability a [ArxaKitBackendPlugin] implements when its package
/// owns the fixture-seeding story for its backend.
///
/// kit/data cannot name the plugin's types (no optional dependencies in
/// Dart), so `ArxaKitDataSeeder.push` cannot push rows into a plugin backend
/// directly — it delegates through this seam instead:
///
/// ```dart
/// class ArxaKitCairnBackend implements ArxaKitBackendPlugin, ArxaKitPluginSeeder {
///   ...
/// }
/// ```
///
/// Implementations load [fixtureAssets] through `ArxaKitFixtureLoader`
/// themselves (they hold the id service and schema registry from their
/// `initialize` call) and write the canonical rows through their own write
/// path — canonical ids are deterministic (ADR-0001), so every implementation
/// is expected to be idempotent by construction.
abstract interface class ArxaKitPluginSeeder {
  /// Seed the given bundled fixture assets into the backend. [assetReader]
  /// overrides the composition-root reader (tests and `dart run` tooling pass
  /// a `ArxaKitMemoryAssetReader`).
  Future<void> seedFixtures(
    List<String> fixtureAssets, {
    ArxaKitAssetReader? assetReader,
  });
}
