import 'package:flutter/foundation.dart';

import 'kit_lat_lng.dart';
import 'kit_map_marker.dart';

/// Base map style. Providers map this to their nearest native equivalent
/// (Apple Maps has no terrain style — it falls back to standard).
enum KitMapType { normal, satellite, hybrid, terrain }

/// Declarative configuration for a [KitMapView].
///
/// Markers are config-driven: change the set and rebuild the widget. Camera
/// moves after creation go through [KitMapController].
@immutable
class KitMapConfig {
  const KitMapConfig({
    required this.initialCameraPosition,
    this.markers = const <KitMapMarker>{},
    this.mapType = KitMapType.normal,
    this.myLocationEnabled = false,
    this.zoomControlsEnabled = true,
    this.compassEnabled = true,
    this.onTap,
  });

  final KitCameraPosition initialCameraPosition;
  final Set<KitMapMarker> markers;
  final KitMapType mapType;
  final bool myLocationEnabled;
  final bool zoomControlsEnabled;
  final bool compassEnabled;

  /// Called with the tapped coordinate when the user taps bare map.
  final ValueChanged<KitLatLng>? onTap;

  KitMapConfig copyWith({
    KitCameraPosition? initialCameraPosition,
    Set<KitMapMarker>? markers,
    KitMapType? mapType,
    bool? myLocationEnabled,
    bool? zoomControlsEnabled,
    bool? compassEnabled,
    ValueChanged<KitLatLng>? onTap,
  }) =>
      KitMapConfig(
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
