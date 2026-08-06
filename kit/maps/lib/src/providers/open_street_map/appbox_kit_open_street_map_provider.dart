import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../kit_map_provider.dart';
import '../../models/kit_map_config.dart';
import '../tiled/tiled_map_view.dart';

/// Real, wired OpenStreetMap backend (flutter_map, pure Dart — no native
/// SDK, no API key, fully simulator/emulator/web-testable).
///
/// Two OSM tile-usage-policy requirements are honored by construction:
/// [userAgentPackageName] is a required constructor parameter (OSM blocks
/// generic user agents — pass the host app's real package ID, e.g.
/// `com.example.myapp`), and an attribution overlay is always rendered.
/// Tile caching is handled by flutter_map itself (built-in since 8.2).
///
/// `KitMapConfig.mapType` is ignored: the standard OSM tile server only
/// ships the default street style.
class OpenStreetMapProvider implements KitMapProvider {
  OpenStreetMapProvider({
    required this.userAgentPackageName,
    this.tileProvider,
  });

  /// Host app's package ID — REQUIRED by the OSM tile-usage policy.
  final String userAgentPackageName;

  /// Injectable for widget tests so no HTTP happens; see
  /// [TiledMapView.tileProvider].
  final TileProvider? tileProvider;

  @override
  KitMapProviderKind get kind => KitMapProviderKind.openStreetMap;

  @override
  Widget buildMap({
    required KitMapConfig config,
    KitMapCreatedCallback? onMapCreated,
  }) {
    return TiledMapView(
      config: config,
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: userAgentPackageName,
      attribution: const SimpleAttributionWidget(
        source: Text('OpenStreetMap contributors'),
      ),
      tileProvider: tileProvider,
      onMapCreated: onMapCreated,
    );
  }
}
