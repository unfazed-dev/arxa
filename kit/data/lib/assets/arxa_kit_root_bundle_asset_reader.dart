import 'package:flutter/services.dart' show rootBundle;

import 'arxa_kit_asset_reader.dart';

/// Flutter-backed [ArxaKitAssetReader] — the production adapter. Reads bundled
/// assets through `rootBundle.loadString`. This is the default reader wired
/// by `ArxaKitData.initialize` when the host passes no [ArxaKitAssetReader].
///
/// Lives in its own file (and away from [ArxaKitAssetReader]) so the port stays
/// pure-Dart-importable; only this adapter imports Flutter.
class ArxaKitRootBundleAssetReader implements ArxaKitAssetReader {
  const ArxaKitRootBundleAssetReader();

  @override
  Future<String> readString(String path) => rootBundle.loadString(path);
}
