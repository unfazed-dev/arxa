import 'package:flutter/foundation.dart';

/// A geographic coordinate, owned by arxa_kit_maps so app code never
/// imports a map SDK's LatLng type directly.
@immutable
class ArxaKitLatLng {
  const ArxaKitLatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is ArxaKitLatLng &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'ArxaKitLatLng($latitude, $longitude)';
}

/// A rectangular region described by its south-west and north-east corners.
@immutable
class ArxaKitLatLngBounds {
  const ArxaKitLatLngBounds({required this.southwest, required this.northeast});

  final ArxaKitLatLng southwest;
  final ArxaKitLatLng northeast;

  @override
  bool operator ==(Object other) =>
      other is ArxaKitLatLngBounds &&
      other.southwest == southwest &&
      other.northeast == northeast;

  @override
  int get hashCode => Object.hash(southwest, northeast);

  @override
  String toString() => 'ArxaKitLatLngBounds($southwest, $northeast)';
}

/// A camera position: where the map is looking and how.
@immutable
class ArxaKitCameraPosition {
  const ArxaKitCameraPosition({
    required this.target,
    this.zoom = 14,
    this.bearing = 0,
    this.tilt = 0,
  });

  final ArxaKitLatLng target;
  final double zoom;
  final double bearing;
  final double tilt;

  ArxaKitCameraPosition copyWith({
    ArxaKitLatLng? target,
    double? zoom,
    double? bearing,
    double? tilt,
  }) =>
      ArxaKitCameraPosition(
        target: target ?? this.target,
        zoom: zoom ?? this.zoom,
        bearing: bearing ?? this.bearing,
        tilt: tilt ?? this.tilt,
      );

  @override
  bool operator ==(Object other) =>
      other is ArxaKitCameraPosition &&
      other.target == target &&
      other.zoom == zoom &&
      other.bearing == bearing &&
      other.tilt == tilt;

  @override
  int get hashCode => Object.hash(target, zoom, bearing, tilt);

  @override
  String toString() =>
      'ArxaKitCameraPosition(target: $target, zoom: $zoom, bearing: $bearing, '
      'tilt: $tilt)';
}
