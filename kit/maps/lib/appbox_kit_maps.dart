/// Maps port for appbox_kit apps — a plugin-neutral [AppBoxKitMapView] backed by
/// Google Maps (Android/web/desktop), Apple Maps (iOS), OpenStreetMap, and
/// Mapbox (both pure-Dart via flutter_map). Standalone: no
/// stacked/appbox_kit dependency.
library;

export 'src/appbox_kit_map_provider.dart'
    show
        AppBoxKitMapController,
        AppBoxKitMapCreatedCallback,
        AppBoxKitMapProvider,
        AppBoxKitMapProviderKind,
        appBoxKitDefaultProviderFor;
export 'src/models/appbox_kit_lat_lng.dart';
export 'src/models/appbox_kit_map_config.dart';
export 'src/models/appbox_kit_map_marker.dart';
export 'src/providers/apple/appbox_kit_apple_maps_provider.dart';
export 'src/providers/google/appbox_kit_google_maps_provider.dart';
export 'src/providers/mapbox/appbox_kit_mapbox_provider.dart';
export 'src/providers/open_street_map/appbox_kit_open_street_map_provider.dart';
export 'src/widgets/appbox_kit_map_view.dart';
