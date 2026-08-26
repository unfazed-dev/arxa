import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../arxa_kit_map_provider.dart';
import '../../models/arxa_kit_lat_lng.dart';
import '../../models/arxa_kit_map_config.dart';
import '../../models/arxa_kit_map_marker.dart';

/// Shared flutter_map builder behind the tile-based providers
/// ([ArxaKitOpenStreetMapProvider], [ArxaKitMapboxProvider]). Both are pure-Dart
/// flutter_map backends — no native SDK — that differ only in tile URL,
/// tile geometry (256px vs Mapbox's 512px retina tiles), and attribution.
///
/// ArxaKitMapConfig fields with no flutter_map equivalent are intentionally not
/// honored here: `myLocationEnabled` (needs a location plugin),
/// `zoomControlsEnabled` / `compassEnabled` (flutter_map renders neither
/// chrome), and `ArxaKitCameraPosition.tilt` (2D tile renderer). `mapType` is
/// resolved by each provider into a tile style.
class ArxaKitTiledMapView extends StatefulWidget {
  const ArxaKitTiledMapView({
    super.key,
    required this.config,
    required this.urlTemplate,
    required this.userAgentPackageName,
    required this.attribution,
    this.tileDimension = 256,
    this.zoomOffset = 0,
    this.tileProvider,
    this.onMapCreated,
  });

  final ArxaKitMapConfig config;

  /// Tile URL template, e.g. `https://tile.openstreetmap.org/{z}/{x}/{y}.png`.
  final String urlTemplate;

  /// Plumbs to `TileLayer.userAgentPackageName` — the OSM tile-usage policy
  /// blocks generic user agents, so providers make this a real value.
  final String userAgentPackageName;

  /// Attribution overlay (required by both OSM and Mapbox tile licenses).
  final Widget attribution;

  /// Tile edge length in px — 256 standard, 512 for Mapbox retina tiles
  /// (paired with [zoomOffset] -1).
  final int tileDimension;
  final double zoomOffset;

  /// Injectable for widget tests: pass a fake serving in-memory images so
  /// no HTTP happens. Null in production = flutter_map's NetworkTileProvider
  /// (built-in tile caching since 8.2, per the OSM usage policy).
  final TileProvider? tileProvider;

  final ArxaKitMapCreatedCallback? onMapCreated;

  @override
  State<ArxaKitTiledMapView> createState() => _TiledMapViewState();
}

class _TiledMapViewState extends State<ArxaKitTiledMapView> {
  final MapController _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final camera = config.initialCameraPosition;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter:
            LatLng(camera.target.latitude, camera.target.longitude),
        initialZoom: camera.zoom,
        initialRotation: camera.bearing,
        onTap: config.onTap == null
            ? null
            : (_, latLng) =>
                config.onTap!(ArxaKitLatLng(latLng.latitude, latLng.longitude)),
        onMapReady: () => widget.onMapCreated
            ?.call(_TiledKitMapController(_mapController)),
      ),
      children: [
        TileLayer(
          urlTemplate: widget.urlTemplate,
          userAgentPackageName: widget.userAgentPackageName,
          tileDimension: widget.tileDimension,
          zoomOffset: widget.zoomOffset,
          tileProvider: widget.tileProvider,
        ),
        MarkerLayer(markers: config.markers.map(_toMarker).toList()),
        widget.attribution,
      ],
    );
  }

  static Marker _toMarker(ArxaKitMapMarker marker) {
    final tooltip =
        [marker.title, marker.snippet].whereType<String>().join('\n');
    return Marker(
      key: ValueKey('kit-marker-${marker.id}'),
      point: LatLng(marker.position.latitude, marker.position.longitude),
      // Pin tip sits on the coordinate, like the native SDKs' anchors.
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: marker.onTap,
        child: Tooltip(
          message: tooltip,
          child: const Icon(Icons.location_pin, size: 36),
        ),
      ),
    );
  }
}

class _TiledKitMapController implements ArxaKitMapController {
  _TiledKitMapController(this._inner);

  final MapController _inner;

  @override
  Future<void> moveCamera(ArxaKitCameraPosition position) async {
    _inner.moveAndRotate(
      LatLng(position.target.latitude, position.target.longitude),
      position.zoom,
      position.bearing,
    );
  }

  // kimitail: flutter_map core has no animated camera API — jumps instead.
  // Add flutter_map_animations if smooth flight ever matters.
  @override
  Future<void> animateCamera(ArxaKitCameraPosition position) =>
      moveCamera(position);
}
