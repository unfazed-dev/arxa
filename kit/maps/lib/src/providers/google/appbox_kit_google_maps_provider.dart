import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

import '../../appbox_kit_map_provider.dart';
import '../../models/appbox_kit_lat_lng.dart';
import '../../models/appbox_kit_map_config.dart';
import '../../models/appbox_kit_map_marker.dart';

/// Real, wired Google Maps backend (google_maps_flutter).
///
/// Platform setup (API key in AndroidManifest.xml / AppDelegate / index.html)
/// is host-app responsibility — see README.
class AppBoxKitGoogleMapsProvider implements AppBoxKitMapProvider {
  @override
  AppBoxKitMapProviderKind get kind => AppBoxKitMapProviderKind.google;

  @override
  Widget buildMap({
    required AppBoxKitMapConfig config,
    AppBoxKitMapCreatedCallback? onMapCreated,
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
              config.onTap!(AppBoxKitLatLng(latLng.latitude, latLng.longitude)),
      onMapCreated: onMapCreated == null
          ? null
          : (controller) =>
              onMapCreated(_GoogleKitMapController(controller)),
    );
  }

  static gmaps.CameraPosition _toCamera(AppBoxKitCameraPosition position) =>
      gmaps.CameraPosition(
        target: gmaps.LatLng(
          position.target.latitude,
          position.target.longitude,
        ),
        zoom: position.zoom,
        bearing: position.bearing,
        tilt: position.tilt,
      );

  static gmaps.Marker _toMarker(AppBoxKitMapMarker marker) => gmaps.Marker(
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

  static gmaps.MapType _toMapType(AppBoxKitMapType type) => switch (type) {
        AppBoxKitMapType.normal => gmaps.MapType.normal,
        AppBoxKitMapType.satellite => gmaps.MapType.satellite,
        AppBoxKitMapType.hybrid => gmaps.MapType.hybrid,
        AppBoxKitMapType.terrain => gmaps.MapType.terrain,
      };
}

class _GoogleKitMapController implements AppBoxKitMapController {
  _GoogleKitMapController(this._inner);

  final gmaps.GoogleMapController _inner;

  @override
  Future<void> moveCamera(AppBoxKitCameraPosition position) => _inner.moveCamera(
        gmaps.CameraUpdate.newCameraPosition(
          AppBoxKitGoogleMapsProvider._toCamera(position),
        ),
      );

  @override
  Future<void> animateCamera(AppBoxKitCameraPosition position) =>
      _inner.animateCamera(
        gmaps.CameraUpdate.newCameraPosition(
          AppBoxKitGoogleMapsProvider._toCamera(position),
        ),
      );
}
