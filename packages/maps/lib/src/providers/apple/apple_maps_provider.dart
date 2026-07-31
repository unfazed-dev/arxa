import 'package:apple_maps_flutter/apple_maps_flutter.dart' as amaps;
import 'package:flutter/widgets.dart';

import '../../kit_map_provider.dart';
import '../../models/kit_lat_lng.dart';
import '../../models/kit_map_config.dart';
import '../../models/kit_map_marker.dart';

/// Real, wired Apple Maps backend (apple_maps_flutter) — iOS only, no API
/// key required.
///
/// MAINTENANCE RISK: apple_maps_flutter's release cadence is slow (17+
/// months between publishes at time of wiring). It is kept because it is
/// the only first-party-MapKit option; if it breaks against a future
/// Flutter, swap [defaultProviderFor] to [GoogleMapsProvider] on iOS.
class AppleMapsProvider implements KitMapProvider {
  @override
  KitMapProviderKind get kind => KitMapProviderKind.apple;

  @override
  Widget buildMap({
    required KitMapConfig config,
    KitMapCreatedCallback? onMapCreated,
  }) {
    return amaps.AppleMap(
      initialCameraPosition: _toCamera(config.initialCameraPosition),
      annotations: config.markers.map(_toAnnotation).toSet(),
      mapType: _toMapType(config.mapType),
      myLocationEnabled: config.myLocationEnabled,
      compassEnabled: config.compassEnabled,
      onTap: config.onTap == null
          ? null
          : (latLng) =>
              config.onTap!(KitLatLng(latLng.latitude, latLng.longitude)),
      onMapCreated: onMapCreated == null
          ? null
          : (controller) => onMapCreated(_AppleKitMapController(controller)),
    );
  }

  static amaps.CameraPosition _toCamera(KitCameraPosition position) =>
      amaps.CameraPosition(
        target: amaps.LatLng(
          position.target.latitude,
          position.target.longitude,
        ),
        zoom: position.zoom,
        heading: position.bearing,
        pitch: position.tilt,
      );

  static amaps.Annotation _toAnnotation(KitMapMarker marker) =>
      amaps.Annotation(
        annotationId: amaps.AnnotationId(marker.id),
        position: amaps.LatLng(
          marker.position.latitude,
          marker.position.longitude,
        ),
        infoWindow: amaps.InfoWindow(
          title: marker.title,
          snippet: marker.snippet,
        ),
        onTap: marker.onTap,
      );

  /// Apple Maps has no terrain style; terrain falls back to standard.
  static amaps.MapType _toMapType(KitMapType type) => switch (type) {
        KitMapType.normal || KitMapType.terrain => amaps.MapType.standard,
        KitMapType.satellite => amaps.MapType.satellite,
        KitMapType.hybrid => amaps.MapType.hybrid,
      };
}

class _AppleKitMapController implements KitMapController {
  _AppleKitMapController(this._inner);

  final amaps.AppleMapController _inner;

  @override
  Future<void> moveCamera(KitCameraPosition position) => _inner.moveCamera(
        amaps.CameraUpdate.newCameraPosition(
          AppleMapsProvider._toCamera(position),
        ),
      );

  @override
  Future<void> animateCamera(KitCameraPosition position) =>
      _inner.animateCamera(
        amaps.CameraUpdate.newCameraPosition(
          AppleMapsProvider._toCamera(position),
        ),
      );
}
