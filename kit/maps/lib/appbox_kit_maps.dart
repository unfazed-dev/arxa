/// Maps port for appbox_kit apps — a plugin-neutral [KitMapView] backed by
/// Google Maps (Android/web/desktop) and Apple Maps (iOS), with stubs for
/// OpenStreetMap and Mapbox. Standalone: no stacked/appbox_kit dependency.
library;

export 'src/kit_map_provider.dart'
    show
        KitMapController,
        KitMapCreatedCallback,
        KitMapProvider,
        KitMapProviderKind,
        defaultProviderFor;
export 'src/models/kit_lat_lng.dart';
export 'src/models/kit_map_config.dart';
export 'src/models/kit_map_marker.dart';
export 'src/providers/apple/apple_maps_provider.dart';
export 'src/providers/google/google_maps_provider.dart';
export 'src/providers/mapbox/mapbox_provider.dart';
export 'src/providers/open_street_map/open_street_map_provider.dart';
export 'src/widgets/kit_map_view.dart';
