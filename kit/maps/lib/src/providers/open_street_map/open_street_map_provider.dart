import 'package:flutter/widgets.dart';

import '../../kit_map_provider.dart';
import '../../models/kit_map_config.dart';

/// STUB — OpenStreetMap backend, not yet wired.
///
/// TODO(appbox_kit_maps): implement against `flutter_map` (^8.x, actively
/// maintained, tile-based, no API key for OSM tiles) and add it to
/// pubspec.yaml. Deliberately NOT a dependency today so hosts that never
/// opt in pull nothing.
class OpenStreetMapProvider implements KitMapProvider {
  @override
  KitMapProviderKind get kind => KitMapProviderKind.openStreetMap;

  @override
  Widget buildMap({
    required KitMapConfig config,
    KitMapCreatedCallback? onMapCreated,
  }) {
    throw UnimplementedError(
      'OpenStreetMapProvider is a stub. Wire package:flutter_map and '
      'implement buildMap before selecting KitMapProviderKind.openStreetMap.',
    );
  }
}
