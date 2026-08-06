import 'package:flutter/foundation.dart';

import 'appbox_kit_lat_lng.dart';
import 'appbox_kit_map_marker.dart';

/// Base map style. Providers map this to their nearest native equivalent
/// (Apple Maps has no terrain style — it falls back to standard).
enum AppBoxKitMapType { normal, satellite, hybrid, terrain }

/// Declarative configuration for a [AppBoxKitMapView].
///
/// Markers are config-driven: change the set and rebuild the widget. Camera
/// moves after creation go through [AppBoxKitMapController].
@immutable
class AppBoxKitMapConfig {
  const AppBoxKitMapConfig({
    required this.initialCameraPosition,
    this.markers = const <AppBoxKitMapMarker>{},
    this.mapType = AppBoxKitMapType.normal,
    this.myLocationEnabled = false,
    this.zoomControlsEnabled = true,
    this.compassEnabled = true,
    this.onTap,
  });

  final AppBoxKitCameraPosition initialCameraPosition;
  final Set<AppBoxKitMapMarker> markers;
  final AppBoxKitMapType mapType;
  final bool myLocationEnabled;
  final bool zoomControlsEnabled;
  final bool compassEnabled;

  /// Called with the tapped coordinate when the user taps bare map.
  final ValueChanged<AppBoxKitLatLng>? onTap;

  AppBoxKitMapConfig copyWith({
    AppBoxKitCameraPosition? initialCameraPosition,
    Set<AppBoxKitMapMarker>? markers,
    AppBoxKitMapType? mapType,
    bool? myLocationEnabled,
    bool? zoomControlsEnabled,
    bool? compassEnabled,
    ValueChanged<AppBoxKitLatLng>? onTap,
  }) =>
      AppBoxKitMapConfig(
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
