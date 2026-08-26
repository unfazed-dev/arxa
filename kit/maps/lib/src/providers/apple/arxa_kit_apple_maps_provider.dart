import 'package:apple_maps_flutter/apple_maps_flutter.dart' as amaps;
import 'package:flutter/widgets.dart';

import '../../arxa_kit_map_provider.dart';
import '../../models/arxa_kit_lat_lng.dart';
import '../../models/arxa_kit_map_config.dart';
import '../../models/arxa_kit_map_marker.dart';

/// Real, wired Apple Maps backend (apple_maps_flutter) — iOS only, no API
/// key required.
///
/// MAINTENANCE RISK: apple_maps_flutter's release cadence is slow (17+
/// months between publishes at time of wiring). It is kept because it is
/// the only first-party-MapKit option; if it breaks against a future
/// Flutter, swap [arxaKitDefaultProviderFor] to [ArxaKitGoogleMapsProvider] on iOS.
class ArxaKitAppleMapsProvider implements ArxaKitMapProvider {
  @override
  ArxaKitMapProviderKind get kind => ArxaKitMapProviderKind.apple;

  @override
  Widget buildMap({
    required ArxaKitMapConfig config,
    ArxaKitMapCreatedCallback? onMapCreated,
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
              config.onTap!(ArxaKitLatLng(latLng.latitude, latLng.longitude)),
      onMapCreated: onMapCreated == null
          ? null
          : (controller) => onMapCreated(_AppleKitMapController(controller)),
    );
  }

  static amaps.CameraPosition _toCamera(ArxaKitCameraPosition position) =>
      amaps.CameraPosition(
        target: amaps.LatLng(
          position.target.latitude,
          position.target.longitude,
        ),
        zoom: position.zoom,
        heading: position.bearing,
        pitch: position.tilt,
      );

  static amaps.Annotation _toAnnotation(ArxaKitMapMarker marker) =>
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
  static amaps.MapType _toMapType(ArxaKitMapType type) => switch (type) {
        ArxaKitMapType.normal || ArxaKitMapType.terrain => amaps.MapType.standard,
        ArxaKitMapType.satellite => amaps.MapType.satellite,
        ArxaKitMapType.hybrid => amaps.MapType.hybrid,
      };
}

class _AppleKitMapController implements ArxaKitMapController {
  _AppleKitMapController(this._inner);

  final amaps.AppleMapController _inner;

  @override
  Future<void> moveCamera(ArxaKitCameraPosition position) => _inner.moveCamera(
        amaps.CameraUpdate.newCameraPosition(
          ArxaKitAppleMapsProvider._toCamera(position),
        ),
      );

  @override
  Future<void> animateCamera(ArxaKitCameraPosition position) =>
      _inner.animateCamera(
        amaps.CameraUpdate.newCameraPosition(
          ArxaKitAppleMapsProvider._toCamera(position),
        ),
      );
}
