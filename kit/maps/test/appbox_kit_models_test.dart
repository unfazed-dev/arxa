import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_maps/appbox_kit_maps.dart';

void main() {
  const sydney = AppBoxKitLatLng(-33.8688, 151.2093);
  const melbourne = AppBoxKitLatLng(-37.8136, 144.9631);

  group('AppBoxKitLatLng', () {
    test('kit.maps.models — value equality', () {
      expect(sydney, const AppBoxKitLatLng(-33.8688, 151.2093));
      expect(sydney, isNot(melbourne));
      expect(sydney.hashCode, const AppBoxKitLatLng(-33.8688, 151.2093).hashCode);
    });

    test('kit.maps.models — toString is readable', () {
      expect(sydney.toString(), 'AppBoxKitLatLng(-33.8688, 151.2093)');
    });
  });

  group('AppBoxKitLatLngBounds', () {
    test('kit.maps.models — value equality', () {
      const bounds =
          AppBoxKitLatLngBounds(southwest: melbourne, northeast: sydney);
      expect(
        bounds,
        const AppBoxKitLatLngBounds(southwest: melbourne, northeast: sydney),
      );
      expect(
        bounds,
        isNot(const AppBoxKitLatLngBounds(southwest: sydney, northeast: sydney)),
      );
    });
  });

  group('AppBoxKitCameraPosition', () {
    test('kit.maps.models — defaults and equality', () {
      const camera = AppBoxKitCameraPosition(target: sydney);
      expect(camera.zoom, 14);
      expect(camera.bearing, 0);
      expect(camera.tilt, 0);
      expect(camera, const AppBoxKitCameraPosition(target: sydney));
    });

    test('kit.maps.models — copyWith replaces only requested fields', () {
      const camera = AppBoxKitCameraPosition(target: sydney, zoom: 10);
      final moved = camera.copyWith(target: melbourne, tilt: 30);
      expect(moved.target, melbourne);
      expect(moved.zoom, 10);
      expect(moved.tilt, 30);
      expect(camera.target, sydney, reason: 'original is immutable');
    });
  });

  group('AppBoxKitMapMarker', () {
    test('kit.maps.models — identity is id + position + info window', () {
      const a = AppBoxKitMapMarker(id: 'office', position: sydney, title: 'HQ');
      const b = AppBoxKitMapMarker(id: 'office', position: sydney, title: 'HQ');
      expect(a, b);
      expect(a, isNot(const AppBoxKitMapMarker(id: 'other', position: sydney)));
    });
  });

  group('AppBoxKitMapConfig', () {
    test('kit.maps.models — defaults', () {
      const config =
          AppBoxKitMapConfig(initialCameraPosition: AppBoxKitCameraPosition(target: sydney));
      expect(config.markers, isEmpty);
      expect(config.mapType, AppBoxKitMapType.normal);
      expect(config.myLocationEnabled, isFalse);
      expect(config.zoomControlsEnabled, isTrue);
      expect(config.compassEnabled, isTrue);
    });

    test('kit.maps.models — copyWith swaps markers without touching camera', () {
      const config =
          AppBoxKitMapConfig(initialCameraPosition: AppBoxKitCameraPosition(target: sydney));
      final updated = config.copyWith(
        markers: {const AppBoxKitMapMarker(id: 'm1', position: melbourne)},
      );
      expect(updated.markers, hasLength(1));
      expect(updated.initialCameraPosition.target, sydney);
    });
  });
}
