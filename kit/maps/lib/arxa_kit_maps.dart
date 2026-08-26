/// Maps port for arxa_kit apps — a plugin-neutral [ArxaKitMapView] backed by
/// Google Maps (Android/web/desktop), Apple Maps (iOS), OpenStreetMap, and
/// Mapbox (both pure-Dart via flutter_map). Standalone: no
/// stacked/arxa_kit dependency.
library;

export 'src/arxa_kit_map_provider.dart'
    show
        ArxaKitMapController,
        ArxaKitMapCreatedCallback,
        ArxaKitMapProvider,
        ArxaKitMapProviderKind,
        arxaKitDefaultProviderFor;
export 'src/models/arxa_kit_lat_lng.dart';
export 'src/models/arxa_kit_map_config.dart';
export 'src/models/arxa_kit_map_marker.dart';
export 'src/providers/apple/arxa_kit_apple_maps_provider.dart';
export 'src/providers/google/arxa_kit_google_maps_provider.dart';
export 'src/providers/mapbox/arxa_kit_mapbox_provider.dart';
export 'src/providers/open_street_map/arxa_kit_open_street_map_provider.dart';
export 'src/widgets/arxa_kit_map_view.dart';
