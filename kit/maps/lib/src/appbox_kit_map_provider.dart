import 'package:flutter/widgets.dart';

import 'models/appbox_kit_lat_lng.dart';
import 'models/appbox_kit_map_config.dart';
import 'providers/apple/appbox_kit_apple_maps_provider.dart';
import 'providers/google/appbox_kit_google_maps_provider.dart';

/// Which native map backend a provider wraps.
enum AppBoxKitMapProviderKind { google, apple, openStreetMap, mapbox }

/// Post-creation camera handle for a live map, owned by appbox_kit_maps.
///
/// Markers are intentionally NOT controlled here — they are declarative via
/// [AppBoxKitMapConfig.markers]; rebuild the [AppBoxKitMapView] with a new set instead.
abstract interface class AppBoxKitMapController {
  /// Jump the camera immediately.
  Future<void> moveCamera(AppBoxKitCameraPosition position);

  /// Animate the camera.
  Future<void> animateCamera(AppBoxKitCameraPosition position);
}

/// Signature invoked once the native map is ready.
typedef AppBoxKitMapCreatedCallback = void Function(AppBoxKitMapController controller);

/// Port every map backend implements. App code depends on this interface
/// (usually indirectly through [AppBoxKitMapView]) — never on a map SDK.
abstract interface class AppBoxKitMapProvider {
  AppBoxKitMapProviderKind get kind;

  /// Builds the platform map widget for [config].
  Widget buildMap({
    required AppBoxKitMapConfig config,
    AppBoxKitMapCreatedCallback? onMapCreated,
  });
}

/// Default provider resolution: Apple Maps on iOS (first-party SDK, no API
/// key), Google Maps everywhere else (Android, web, desktop embeddings).
AppBoxKitMapProvider appBoxKitDefaultProviderFor(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.iOS:
      return AppBoxKitAppleMapsProvider();
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return AppBoxKitGoogleMapsProvider();
  }
}
