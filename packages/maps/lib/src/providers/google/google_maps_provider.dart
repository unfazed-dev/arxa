import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

import '../../kit_map_provider.dart';
import '../../models/kit_lat_lng.dart';
import '../../models/kit_map_config.dart';
import '../../models/kit_map_marker.dart';

/// Real, wired Google Maps backend (google_maps_flutter).
///
/// Platform setup (API key in AndroidManifest.xml / AppDelegate / index.html)
/// is host-app responsibility — see README.
class GoogleMapsProvider implements KitMapProvider {
  @override
  KitMapProviderKind get kind => KitMapProviderKind.google;

  @override
  Widget buildMap({
    required KitMapConfig config,
    KitMapCreatedCallback? onMapCreated,
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
              config.onTap!(KitLatLng(latLng.latitude, latLng.longitude)),
      onMapCreated: onMapCreated == null
          ? null
          : (controller) =>
              onMapCreated(_GoogleKitMapController(controller)),
    );
  }

  static gmaps.CameraPosition _toCamera(KitCameraPosition position) =>
      gmaps.CameraPosition(
        target: gmaps.LatLng(
          position.target.latitude,
          position.target.longitude,
        ),
        zoom: position.zoom,
        bearing: position.bearing,
        tilt: position.tilt,
      );

  static gmaps.Marker _toMarker(KitMapMarker marker) => gmaps.Marker(
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

  static gmaps.MapType _toMapType(KitMapType type) => switch (type) {
        KitMapType.normal => gmaps.MapType.normal,
        KitMapType.satellite => gmaps.MapType.satellite,
        KitMapType.hybrid => gmaps.MapType.hybrid,
        KitMapType.terrain => gmaps.MapType.terrain,
      };
}

class _GoogleKitMapController implements KitMapController {
  _GoogleKitMapController(this._inner);

  final gmaps.GoogleMapController _inner;

  @override
  Future<void> moveCamera(KitCameraPosition position) => _inner.moveCamera(
        gmaps.CameraUpdate.newCameraPosition(
          GoogleMapsProvider._toCamera(position),
        ),
      );

  @override
  Future<void> animateCamera(KitCameraPosition position) =>
      _inner.animateCamera(
        gmaps.CameraUpdate.newCameraPosition(
          GoogleMapsProvider._toCamera(position),
        ),
      );
}
