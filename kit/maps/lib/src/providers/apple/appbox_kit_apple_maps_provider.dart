import 'package:apple_maps_flutter/apple_maps_flutter.dart' as amaps;
import 'package:flutter/widgets.dart';

import '../../appbox_kit_map_provider.dart';
import '../../models/appbox_kit_lat_lng.dart';
import '../../models/appbox_kit_map_config.dart';
import '../../models/appbox_kit_map_marker.dart';

/// Real, wired Apple Maps backend (apple_maps_flutter) — iOS only, no API
/// key required.
///
/// MAINTENANCE RISK: apple_maps_flutter's release cadence is slow (17+
/// months between publishes at time of wiring). It is kept because it is
/// the only first-party-MapKit option; if it breaks against a future
/// Flutter, swap [appBoxKitDefaultProviderFor] to [AppBoxKitGoogleMapsProvider] on iOS.
class AppBoxKitAppleMapsProvider implements AppBoxKitMapProvider {
  @override
  AppBoxKitMapProviderKind get kind => AppBoxKitMapProviderKind.apple;

  @override
  Widget buildMap({
    required AppBoxKitMapConfig config,
    AppBoxKitMapCreatedCallback? onMapCreated,
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
              config.onTap!(AppBoxKitLatLng(latLng.latitude, latLng.longitude)),
      onMapCreated: onMapCreated == null
          ? null
          : (controller) => onMapCreated(_AppleKitMapController(controller)),
    );
  }

  static amaps.CameraPosition _toCamera(AppBoxKitCameraPosition position) =>
      amaps.CameraPosition(
        target: amaps.LatLng(
          position.target.latitude,
          position.target.longitude,
        ),
        zoom: position.zoom,
        heading: position.bearing,
        pitch: position.tilt,
      );

  static amaps.Annotation _toAnnotation(AppBoxKitMapMarker marker) =>
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
  static amaps.MapType _toMapType(AppBoxKitMapType type) => switch (type) {
        AppBoxKitMapType.normal || AppBoxKitMapType.terrain => amaps.MapType.standard,
        AppBoxKitMapType.satellite => amaps.MapType.satellite,
        AppBoxKitMapType.hybrid => amaps.MapType.hybrid,
      };
}

class _AppleKitMapController implements AppBoxKitMapController {
  _AppleKitMapController(this._inner);

  final amaps.AppleMapController _inner;

  @override
  Future<void> moveCamera(AppBoxKitCameraPosition position) => _inner.moveCamera(
        amaps.CameraUpdate.newCameraPosition(
          AppBoxKitAppleMapsProvider._toCamera(position),
        ),
      );

  @override
  Future<void> animateCamera(AppBoxKitCameraPosition position) =>
      _inner.animateCamera(
        amaps.CameraUpdate.newCameraPosition(
          AppBoxKitAppleMapsProvider._toCamera(position),
        ),
      );
}
