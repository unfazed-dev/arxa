import 'package:flutter/services.dart' show rootBundle;

import 'kit_asset_reader.dart';

/// Flutter-backed [KitAssetReader] — the production adapter. Reads bundled
/// assets through `rootBundle.loadString`. This is the default reader wired
/// by `KitData.initialize` when the host passes no [KitAssetReader].
///
/// Lives in its own file (and away from [KitAssetReader]) so the port stays
/// pure-Dart-importable; only this adapter imports Flutter.
class KitRootBundleAssetReader implements KitAssetReader {
  const KitRootBundleAssetReader();

  @override
  Future<String> readString(String path) => rootBundle.loadString(path);
}
