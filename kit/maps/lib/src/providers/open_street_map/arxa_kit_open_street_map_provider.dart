import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../arxa_kit_map_provider.dart';
import '../../models/arxa_kit_map_config.dart';
import '../tiled/arxa_kit_tiled_map_view.dart';

/// Real, wired OpenStreetMap backend (flutter_map, pure Dart — no native
/// SDK, no API key, fully simulator/emulator/web-testable).
///
/// Two OSM tile-usage-policy requirements are honored by construction:
/// [userAgentPackageName] is a required constructor parameter (OSM blocks
/// generic user agents — pass the host app's real package ID, e.g.
/// `com.example.myapp`), and an attribution overlay is always rendered.
/// Tile caching is handled by flutter_map itself (built-in since 8.2).
///
/// `ArxaKitMapConfig.mapType` is ignored: the standard OSM tile server only
/// ships the default street style.
class ArxaKitOpenStreetMapProvider implements ArxaKitMapProvider {
  ArxaKitOpenStreetMapProvider({
    required this.userAgentPackageName,
    this.tileProvider,
  });

  /// Host app's package ID — REQUIRED by the OSM tile-usage policy.
  final String userAgentPackageName;

  /// Injectable for widget tests so no HTTP happens; see
  /// [ArxaKitTiledMapView.tileProvider].
  final TileProvider? tileProvider;

  @override
  ArxaKitMapProviderKind get kind => ArxaKitMapProviderKind.openStreetMap;

  @override
  Widget buildMap({
    required ArxaKitMapConfig config,
    ArxaKitMapCreatedCallback? onMapCreated,
  }) {
    return ArxaKitTiledMapView(
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
