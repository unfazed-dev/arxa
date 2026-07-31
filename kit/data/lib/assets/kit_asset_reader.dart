/// Pure-Dart port for reading bundled asset strings, decoupling the seed
/// loader and the fake auth service from `package:flutter/services.dart`
/// (`AssetBundle` / `rootBundle`).
///
/// Inject a [KitRootBundleAssetReader] in a Flutter app, or a
/// [KitMemoryAssetReader] under `dart run` tooling or unit tests. Neither
/// `KitFixtureLoader` nor `KitSeedAuthService` imports Flutter — they depend
/// only on this port, so the seed data path is testable without a Flutter
/// binding.
abstract interface class KitAssetReader {
  /// Returns the UTF-8 string at the bundled-asset [path].
  Future<String> readString(String path);
}

/// In-memory [KitAssetReader] for tests and pure-Dart `dart run` tooling.
/// No Flutter binding required.
class KitMemoryAssetReader implements KitAssetReader {
  KitMemoryAssetReader(this.assets);

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
