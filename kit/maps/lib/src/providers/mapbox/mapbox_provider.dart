import 'package:flutter/widgets.dart';

import '../../kit_map_provider.dart';
import '../../models/kit_map_config.dart';

/// STUB — Mapbox backend, not yet wired.
///
/// TODO(appbox_kit_maps): implement against `mapbox_maps_flutter` (^2.x)
/// and add it to pubspec.yaml. Requires MapboxOptions.setAccessToken(token)
/// before first map build. Deliberately NOT a dependency today so hosts
/// that never opt in pull nothing.
class MapboxProvider implements KitMapProvider {
  @override
  KitMapProviderKind get kind => KitMapProviderKind.mapbox;

  @override
  Widget buildMap({
    required KitMapConfig config,
    KitMapCreatedCallback? onMapCreated,
  }) {
    throw UnimplementedError(
      'MapboxProvider is a stub. Wire package:mapbox_maps_flutter, call '
      'MapboxOptions.setAccessToken, and implement buildMap before '
      'selecting KitMapProviderKind.mapbox.',
    );
  }
}
