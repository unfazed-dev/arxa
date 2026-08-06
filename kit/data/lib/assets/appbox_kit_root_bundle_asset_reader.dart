import 'package:flutter/services.dart' show rootBundle;

import 'appbox_kit_asset_reader.dart';

/// Flutter-backed [AppBoxKitAssetReader] — the production adapter. Reads bundled
/// assets through `rootBundle.loadString`. This is the default reader wired
/// by `AppBoxKitData.initialize` when the host passes no [AppBoxKitAssetReader].
///
/// Lives in its own file (and away from [AppBoxKitAssetReader]) so the port stays
/// pure-Dart-importable; only this adapter imports Flutter.
class AppBoxKitRootBundleAssetReader implements AppBoxKitAssetReader {
  const AppBoxKitRootBundleAssetReader();

  @override
  Future<String> readString(String path) => rootBundle.loadString(path);
}
