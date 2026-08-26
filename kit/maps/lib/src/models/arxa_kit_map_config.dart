import 'package:flutter/foundation.dart';

import 'arxa_kit_lat_lng.dart';
import 'arxa_kit_map_marker.dart';

/// Base map style. Providers map this to their nearest native equivalent
/// (Apple Maps has no terrain style — it falls back to standard).
enum ArxaKitMapType { normal, satellite, hybrid, terrain }

/// Declarative configuration for a [ArxaKitMapView].
///
/// Markers are config-driven: change the set and rebuild the widget. Camera
/// moves after creation go through [ArxaKitMapController].
@immutable
class ArxaKitMapConfig {
  const ArxaKitMapConfig({
    required this.initialCameraPosition,
    this.markers = const <ArxaKitMapMarker>{},
    this.mapType = ArxaKitMapType.normal,
    this.myLocationEnabled = false,
    this.zoomControlsEnabled = true,
    this.compassEnabled = true,
    this.onTap,
  });

  final ArxaKitCameraPosition initialCameraPosition;
  final Set<ArxaKitMapMarker> markers;
  final ArxaKitMapType mapType;
  final bool myLocationEnabled;
  final bool zoomControlsEnabled;
  final bool compassEnabled;

  /// Called with the tapped coordinate when the user taps bare map.
  final ValueChanged<ArxaKitLatLng>? onTap;

  ArxaKitMapConfig copyWith({
    ArxaKitCameraPosition? initialCameraPosition,
    Set<ArxaKitMapMarker>? markers,
    ArxaKitMapType? mapType,
    bool? myLocationEnabled,
    bool? zoomControlsEnabled,
    bool? compassEnabled,
    ValueChanged<ArxaKitLatLng>? onTap,
  }) =>
      ArxaKitMapConfig(
        initialCameraPosition:
            initialCameraPosition ?? this.initialCameraPosition,
        markers: markers ?? this.markers,
        mapType: mapType ?? this.mapType,
        myLocationEnabled: myLocationEnabled ?? this.myLocationEnabled,
        zoomControlsEnabled: zoomControlsEnabled ?? this.zoomControlsEnabled,
        compassEnabled: compassEnabled ?? this.compassEnabled,
        onTap: onTap ?? this.onTap,
      );
}
