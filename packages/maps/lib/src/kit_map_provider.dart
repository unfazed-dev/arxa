import 'package:flutter/widgets.dart';

import 'models/kit_lat_lng.dart';
import 'models/kit_map_config.dart';
import 'providers/apple/apple_maps_provider.dart';
import 'providers/google/google_maps_provider.dart';

/// Which native map backend a provider wraps.
enum KitMapProviderKind { google, apple, openStreetMap, mapbox }

/// Post-creation camera handle for a live map, owned by appbox_kit_maps.
///
/// Markers are intentionally NOT controlled here — they are declarative via
/// [KitMapConfig.markers]; rebuild the [KitMapView] with a new set instead.
abstract interface class KitMapController {
  /// Jump the camera immediately.
  Future<void> moveCamera(KitCameraPosition position);

  /// Animate the camera.
  Future<void> animateCamera(KitCameraPosition position);
}

/// Signature invoked once the native map is ready.
typedef KitMapCreatedCallback = void Function(KitMapController controller);

/// Port every map backend implements. App code depends on this interface
/// (usually indirectly through [KitMapView]) — never on a map SDK.
abstract interface class KitMapProvider {
  KitMapProviderKind get kind;

  /// Builds the platform map widget for [config].
  Widget buildMap({
    required KitMapConfig config,
    KitMapCreatedCallback? onMapCreated,
  });
}

/// Default provider resolution: Apple Maps on iOS (first-party SDK, no API
/// key), Google Maps everywhere else (Android, web, desktop embeddings).
KitMapProvider defaultProviderFor(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.iOS:
      return AppleMapsProvider();
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return GoogleMapsProvider();
  }
}
