import 'package:flutter/foundation.dart';

/// A geographic coordinate, owned by appbox_kit_maps so app code never
/// imports a map SDK's LatLng type directly.
@immutable
class KitLatLng {
  const KitLatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is KitLatLng &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'KitLatLng($latitude, $longitude)';
}

/// A rectangular region described by its south-west and north-east corners.
@immutable
class KitLatLngBounds {
  const KitLatLngBounds({required this.southwest, required this.northeast});

  final KitLatLng southwest;
  final KitLatLng northeast;

  @override
  bool operator ==(Object other) =>
      other is KitLatLngBounds &&
      other.southwest == southwest &&
      other.northeast == northeast;

  @override
  int get hashCode => Object.hash(southwest, northeast);

  @override
  String toString() => 'KitLatLngBounds($southwest, $northeast)';
}

/// A camera position: where the map is looking and how.
@immutable
class KitCameraPosition {
  const KitCameraPosition({
    required this.target,
    this.zoom = 14,
    this.bearing = 0,
    this.tilt = 0,
  });

  final KitLatLng target;
  final double zoom;
  final double bearing;
  final double tilt;

  KitCameraPosition copyWith({
    KitLatLng? target,
    double? zoom,
    double? bearing,
    double? tilt,
  }) =>
      KitCameraPosition(
        target: target ?? this.target,
        zoom: zoom ?? this.zoom,
        bearing: bearing ?? this.bearing,
        tilt: tilt ?? this.tilt,
      );

  @override
  bool operator ==(Object other) =>
      other is KitCameraPosition &&
      other.target == target &&
      other.zoom == zoom &&
      other.bearing == bearing &&
      other.tilt == tilt;

  @override
  int get hashCode => Object.hash(target, zoom, bearing, tilt);

  @override
  String toString() =>
      'KitCameraPosition(target: $target, zoom: $zoom, bearing: $bearing, '
      'tilt: $tilt)';
}
