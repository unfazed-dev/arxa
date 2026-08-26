import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

import '../../arxa_kit_map_provider.dart';
import '../../models/arxa_kit_lat_lng.dart';
import '../../models/arxa_kit_map_config.dart';
import '../../models/arxa_kit_map_marker.dart';

/// Real, wired Google Maps backend (google_maps_flutter).
///
/// Platform setup (API key in AndroidManifest.xml / AppDelegate / index.html)
/// is host-app responsibility — see README.
class ArxaKitGoogleMapsProvider implements ArxaKitMapProvider {
  @override
  ArxaKitMapProviderKind get kind => ArxaKitMapProviderKind.google;

  @override
  Widget buildMap({
    required ArxaKitMapConfig config,
    ArxaKitMapCreatedCallback? onMapCreated,
  }) {
    return gmaps.GoogleMap(
      initialCameraPosition: _toCamera(config.initialCameraPosition),
      markers: config.markers.map(_toMarker).toSet(),
      mapType: _toMapType(config.mapType),
      myLocationEnabled: config.myLocationEnabled,
      zoomControlsEnabled: config.zoomControlsEnabled,
      compassEnabled: config.compassEnabled,
      onTap: config.onTap == null
          ? null
          : (latLng) =>
              config.onTap!(ArxaKitLatLng(latLng.latitude, latLng.longitude)),
      onMapCreated: onMapCreated == null
          ? null
          : (controller) =>
              onMapCreated(_GoogleKitMapController(controller)),
    );
  }

  static gmaps.CameraPosition _toCamera(ArxaKitCameraPosition position) =>
      gmaps.CameraPosition(
        target: gmaps.LatLng(
          position.target.latitude,
          position.target.longitude,
        ),
        zoom: position.zoom,
        bearing: position.bearing,
        tilt: position.tilt,
      );

  static gmaps.Marker _toMarker(ArxaKitMapMarker marker) => gmaps.Marker(
        markerId: gmaps.MarkerId(marker.id),
        position: gmaps.LatLng(
          marker.position.latitude,
          marker.position.longitude,
        ),
        infoWindow: gmaps.InfoWindow(
          title: marker.title,
          snippet: marker.snippet,
        ),
        onTap: marker.onTap,
      );

  static gmaps.MapType _toMapType(ArxaKitMapType type) => switch (type) {
        ArxaKitMapType.normal => gmaps.MapType.normal,
        ArxaKitMapType.satellite => gmaps.MapType.satellite,
        ArxaKitMapType.hybrid => gmaps.MapType.hybrid,
        ArxaKitMapType.terrain => gmaps.MapType.terrain,
      };
}

class _GoogleKitMapController implements ArxaKitMapController {
  _GoogleKitMapController(this._inner);

  final gmaps.GoogleMapController _inner;

  @override
  Future<void> moveCamera(ArxaKitCameraPosition position) => _inner.moveCamera(
        gmaps.CameraUpdate.newCameraPosition(
          ArxaKitGoogleMapsProvider._toCamera(position),
        ),
      );

  @override
  Future<void> animateCamera(ArxaKitCameraPosition position) =>
      _inner.animateCamera(
        gmaps.CameraUpdate.newCameraPosition(
          ArxaKitGoogleMapsProvider._toCamera(position),
        ),
      );
}
