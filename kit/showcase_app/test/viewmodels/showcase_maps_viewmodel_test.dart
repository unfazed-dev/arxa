import 'package:appbox_kit_maps/appbox_kit_maps.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_viewmodel.dart';

void main() {
  group('ShowcaseMapsViewModel', () {
    tearDown(() => locator.reset());

    test(
        'profile-and-gallery-demos.gallery.view-the-maps-demo — '
        'falls back to OpenStreetMap when no Mapbox token is configured', () {
      // given (tests run without --dart-define=MAPBOX_PUBLIC_TOKEN)
      final vm = ShowcaseMapsViewModel();
      // when
      final provider = vm.provider;
      // then
      expect(vm.mapboxAvailable, isFalse);
      expect(provider, isA<AppBoxKitOpenStreetMapProvider>());
      expect(vm.backendLabel, 'OpenStreetMap');
    });

    test(
        'profile-and-gallery-demos.gallery.view-the-maps-demo — '
        'camera opens on London with the two landmark markers', () {
      // given
      final vm = ShowcaseMapsViewModel();
      // when
      final config = vm.config;
      // then
      expect(config.initialCameraPosition.target,
          const AppBoxKitLatLng(51.5074, -0.1278));
      expect(config.initialCameraPosition.zoom, 11);
      expect(config.markers.map((m) => m.id),
          containsAll(<String>['london-eye', 'tower-bridge']));
      expect(
        config.markers.singleWhere((m) => m.id == 'london-eye').position,
        const AppBoxKitLatLng(51.5033, -0.1196),
      );
    });
  });
}
