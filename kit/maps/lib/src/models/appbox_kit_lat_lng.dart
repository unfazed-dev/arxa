import 'package:flutter/foundation.dart';

/// A geographic coordinate, owned by appbox_kit_maps so app code never
/// imports a map SDK's LatLng type directly.
@immutable
class AppBoxKitLatLng {
  const AppBoxKitLatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitLatLng &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'AppBoxKitLatLng($latitude, $longitude)';
}

/// A rectangular region described by its south-west and north-east corners.
@immutable
class AppBoxKitLatLngBounds {
  const AppBoxKitLatLngBounds({required this.southwest, required this.northeast});

  final AppBoxKitLatLng southwest;
  final AppBoxKitLatLng northeast;

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitLatLngBounds &&
      other.southwest == southwest &&
      other.northeast == northeast;

  @override
  int get hashCode => Object.hash(southwest, northeast);

  @override
  String toString() => 'AppBoxKitLatLngBounds($southwest, $northeast)';
}

/// A camera position: where the map is looking and how.
@immutable
class AppBoxKitCameraPosition {
  const AppBoxKitCameraPosition({
    required this.target,
    this.zoom = 14,
    this.bearing = 0,
    this.tilt = 0,
  });

  final AppBoxKitLatLng target;
  final double zoom;
  final double bearing;
  final double tilt;

  AppBoxKitCameraPosition copyWith({
    AppBoxKitLatLng? target,
    double? zoom,
    double? bearing,
    double? tilt,
  }) =>
      AppBoxKitCameraPosition(
        target: target ?? this.target,
        zoom: zoom ?? this.zoom,
        bearing: bearing ?? this.bearing,
        tilt: tilt ?? this.tilt,
      );

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitCameraPosition &&
      other.target == target &&
      other.zoom == zoom &&
      other.bearing == bearing &&
      other.tilt == tilt;

  @override
  int get hashCode => Object.hash(target, zoom, bearing, tilt);

  @override
  String toString() =>
      'AppBoxKitCameraPosition(target: $target, zoom: $zoom, bearing: $bearing, '
      'tilt: $tilt)';
}
