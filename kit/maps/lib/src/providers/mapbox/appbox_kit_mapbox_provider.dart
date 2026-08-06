import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../appbox_kit_map_provider.dart';
import '../../models/appbox_kit_map_config.dart';
import '../tiled/appbox_kit_tiled_map_view.dart';

/// Real, wired Mapbox backend — flutter_map + Mapbox raster tiles (pure
/// Dart, fully simulator/emulator/web-testable).
///
/// Deliberately NOT the native `mapbox_maps_flutter` SDK: that needs a
/// secret `sk.*` downloads token in ~/.netrc and platform setup. Here a
/// public `pk.*` token rides in the tile URL against Mapbox's 512px raster
/// endpoint (retina tiles: `tileDimension: 512, zoomOffset: -1`).
///
/// Token handling: [accessToken] is a publishable `pk.*` key — inject it,
/// never hardcode it. Host apps pass
/// `--dart-define=MAPBOX_PUBLIC_TOKEN=pk....` and read it with
/// `String.fromEnvironment`, matching the `MAPBOX_PUBLIC_TOKEN` entry in
/// config/credentials.catalog.json. The catalog's optional
/// `MAPBOX_SECRET_TOKEN` entry is NOT needed by this provider. An empty
/// token is rejected eagerly (ArgumentError) rather than surfacing as tile
/// 401s at runtime.
class AppBoxKitMapboxProvider implements AppBoxKitMapProvider {
  AppBoxKitMapboxProvider({
    required this.accessToken,
    required this.userAgentPackageName,
    this.tileProvider,
  }) {
    if (accessToken.isEmpty) {
      throw ArgumentError.value(accessToken, 'accessToken',
          'AppBoxKitMapboxProvider needs a public pk.* token — pass '
          '--dart-define=MAPBOX_PUBLIC_TOKEN=pk....');
    }
  }

  /// Public Mapbox access token (`pk.*`). See class docs for injection.
  final String accessToken;

  /// Host app's package ID, plumbed to `TileLayer.userAgentPackageName`.
  final String userAgentPackageName;

  /// Injectable for widget tests so no HTTP happens; see
  /// [AppBoxKitTiledMapView.tileProvider].
  final TileProvider? tileProvider;

  @override
  AppBoxKitMapProviderKind get kind => AppBoxKitMapProviderKind.mapbox;

  @override
  Widget buildMap({
    required AppBoxKitMapConfig config,
    AppBoxKitMapCreatedCallback? onMapCreated,
  }) {
    return AppBoxKitTiledMapView(
      config: config,
      urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/'
          '${_styleFor(config.mapType)}/tiles/512/{z}/{x}/{y}@2x'
          '?access_token=$accessToken',
      userAgentPackageName: userAgentPackageName,
      tileDimension: 512,
      zoomOffset: -1,
      attribution: const SimpleAttributionWidget(
        source: Text('© Mapbox © OpenStreetMap contributors'),
      ),
      tileProvider: tileProvider,
      onMapCreated: onMapCreated,
    );
  }

  /// Mapbox style ID per kit map type.
  static String _styleFor(AppBoxKitMapType type) => switch (type) {
        AppBoxKitMapType.normal => 'streets-v12',
        AppBoxKitMapType.satellite => 'satellite-v9',
        AppBoxKitMapType.hybrid => 'satellite-streets-v12',
        AppBoxKitMapType.terrain => 'outdoors-v12',
      };
}
