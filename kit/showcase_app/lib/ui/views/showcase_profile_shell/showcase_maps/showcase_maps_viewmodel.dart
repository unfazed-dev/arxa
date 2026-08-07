import 'package:appbox_kit_maps/appbox_kit_maps.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// Maps showcase — appbox_kit_maps through the plugin-neutral AppBoxKitMapView.
///
/// Backend: OpenStreetMap by default (no key). Pass
/// `--dart-define=MAPBOX_PUBLIC_TOKEN=pk....` to flip the same AppBoxKitMapView to
/// Mapbox raster tiles — nothing else changes, which is the point of the port.
class ShowcaseMapsViewModel extends BaseViewModel {
  static const _packageId = 'com.appboxkit.appbox_kit_showcase_app';
  static const _mapboxToken = String.fromEnvironment('MAPBOX_PUBLIC_TOKEN');

  bool get mapboxAvailable => _mapboxToken.isNotEmpty;

  String get backendLabel =>
      mapboxAvailable ? 'Mapbox raster tiles' : 'OpenStreetMap';

  AppBoxKitMapProvider get provider => mapboxAvailable
      ? AppBoxKitMapboxProvider(
          accessToken: _mapboxToken,
          userAgentPackageName: _packageId,
        )
      : AppBoxKitOpenStreetMapProvider(userAgentPackageName: _packageId);

  AppBoxKitMapConfig get config => AppBoxKitMapConfig(
        initialCameraPosition: const AppBoxKitCameraPosition(
          target: AppBoxKitLatLng(51.5074, -0.1278), // London
          zoom: 11,
        ),
        markers: {
          const AppBoxKitMapMarker(
            id: 'london-eye',
            position: AppBoxKitLatLng(51.5033, -0.1196),
            title: 'London Eye',
          ),
          const AppBoxKitMapMarker(
            id: 'tower-bridge',
            position: AppBoxKitLatLng(51.5055, -0.0754),
            title: 'Tower Bridge',
          ),
        },
      );
}
