/// Pure-Dart port for reading bundled asset strings, decoupling the seed
/// loader and the fake auth service from `package:flutter/services.dart`
/// (`AssetBundle` / `rootBundle`).
///
/// Inject a [ArxaKitRootBundleAssetReader] in a Flutter app, or a
/// [ArxaKitMemoryAssetReader] under `dart run` tooling or unit tests. Neither
/// `ArxaKitFixtureLoader` nor `ArxaKitSeedAuthService` imports Flutter — they depend
/// only on this port, so the seed data path is testable without a Flutter
/// binding.
abstract interface class ArxaKitAssetReader {
  /// Returns the UTF-8 string at the bundled-asset [path].
  Future<String> readString(String path);
}

/// In-memory [ArxaKitAssetReader] for tests and pure-Dart `dart run` tooling.
/// No Flutter binding required.
class ArxaKitMemoryAssetReader implements ArxaKitAssetReader {
  ArxaKitMemoryAssetReader(this.assets);

  final Map<String, String> assets;

  @override
  Future<String> readString(String path) async {
    final value = assets[path];
    if (value == null) {
      throw ArgumentError('No in-memory asset at "$path"');
    }
    return value;
  }
}
