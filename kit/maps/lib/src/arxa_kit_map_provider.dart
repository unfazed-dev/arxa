import 'package:flutter/widgets.dart';

import 'models/arxa_kit_lat_lng.dart';
import 'models/arxa_kit_map_config.dart';
import 'providers/apple/arxa_kit_apple_maps_provider.dart';
import 'providers/google/arxa_kit_google_maps_provider.dart';

/// Which native map backend a provider wraps.
enum ArxaKitMapProviderKind { google, apple, openStreetMap, mapbox }

/// Post-creation camera handle for a live map, owned by arxa_kit_maps.
///
/// Markers are intentionally NOT controlled here — they are declarative via
/// [ArxaKitMapConfig.markers]; rebuild the [ArxaKitMapView] with a new set instead.
abstract interface class ArxaKitMapController {
  /// Jump the camera immediately.
  Future<void> moveCamera(ArxaKitCameraPosition position);

  /// Animate the camera.
  Future<void> animateCamera(ArxaKitCameraPosition position);
}

/// Signature invoked once the native map is ready.
typedef ArxaKitMapCreatedCallback = void Function(ArxaKitMapController controller);

/// Port every map backend implements. App code depends on this interface
/// (usually indirectly through [ArxaKitMapView]) — never on a map SDK.
abstract interface class ArxaKitMapProvider {
  ArxaKitMapProviderKind get kind;

  /// Builds the platform map widget for [config].
  Widget buildMap({
    required ArxaKitMapConfig config,
    ArxaKitMapCreatedCallback? onMapCreated,
  });
}

/// Default provider resolution: Apple Maps on iOS (first-party SDK, no API
/// key), Google Maps everywhere else (Android, web, desktop embeddings).
ArxaKitMapProvider arxaKitDefaultProviderFor(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.iOS:
      return ArxaKitAppleMapsProvider();
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return ArxaKitGoogleMapsProvider();
  }
}
