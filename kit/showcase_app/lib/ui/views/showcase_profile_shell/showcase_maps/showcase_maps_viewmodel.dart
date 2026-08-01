import 'package:appbox_kit_maps/appbox_kit_maps.dart';
import 'package:stacked/stacked.dart';

/// Maps showcase — appbox_kit_maps through the plugin-neutral KitMapView.
///
/// Backend: OpenStreetMap by default (no key). Pass
/// `--dart-define=MAPBOX_PUBLIC_TOKEN=pk....` to flip the same KitMapView to
/// Mapbox raster tiles — nothing else changes, which is the point of the port.
class ShowcaseMapsViewModel extends BaseViewModel {
  static const _packageId = 'com.appboxkit.appbox_kit_showcase_app';
  static const _mapboxToken = String.fromEnvironment('MAPBOX_PUBLIC_TOKEN');

  bool get mapboxAvailable => _mapboxToken.isNotEmpty;

  String get backendLabel =>
      mapboxAvailable ? 'Mapbox raster tiles' : 'OpenStreetMap';

  KitMapProvider get provider => mapboxAvailable
      ? MapboxProvider(
          accessToken: _mapboxToken,
          userAgentPackageName: _packageId,
        )
      : OpenStreetMapProvider(userAgentPackageName: _packageId);

  KitMapConfig get config => KitMapConfig(
        initialCameraPosition: const KitCameraPosition(
          target: KitLatLng(51.5074, -0.1278), // London
          zoom: 11,
        ),
        markers: {
          const KitMapMarker(
            id: 'london-eye',
            position: KitLatLng(51.5033, -0.1196),
            title: 'London Eye',
          ),
          const KitMapMarker(
            id: 'tower-bridge',
            position: KitLatLng(51.5055, -0.0754),
            title: 'Tower Bridge',
          ),
        },
      );
}
