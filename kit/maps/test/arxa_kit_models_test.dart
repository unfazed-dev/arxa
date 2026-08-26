import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_maps/arxa_kit_maps.dart';

void main() {
  const sydney = ArxaKitLatLng(-33.8688, 151.2093);
  const melbourne = ArxaKitLatLng(-37.8136, 144.9631);

  group('ArxaKitLatLng', () {
    test('kit.maps.models — value equality', () {
      expect(sydney, const ArxaKitLatLng(-33.8688, 151.2093));
      expect(sydney, isNot(melbourne));
      expect(sydney.hashCode, const ArxaKitLatLng(-33.8688, 151.2093).hashCode);
    });

    test('kit.maps.models — toString is readable', () {
      expect(sydney.toString(), 'ArxaKitLatLng(-33.8688, 151.2093)');
    });
  });

  group('ArxaKitLatLngBounds', () {
    test('kit.maps.models — value equality', () {
      const bounds =
          ArxaKitLatLngBounds(southwest: melbourne, northeast: sydney);
      expect(
        bounds,
        const ArxaKitLatLngBounds(southwest: melbourne, northeast: sydney),
      );
      expect(
        bounds,
        isNot(const ArxaKitLatLngBounds(southwest: sydney, northeast: sydney)),
      );
    });
  });

  group('ArxaKitCameraPosition', () {
    test('kit.maps.models — defaults and equality', () {
      const camera = ArxaKitCameraPosition(target: sydney);
      expect(camera.zoom, 14);
      expect(camera.bearing, 0);
      expect(camera.tilt, 0);
      expect(camera, const ArxaKitCameraPosition(target: sydney));
    });

    test('kit.maps.models — copyWith replaces only requested fields', () {
      const camera = ArxaKitCameraPosition(target: sydney, zoom: 10);
      final moved = camera.copyWith(target: melbourne, tilt: 30);
      expect(moved.target, melbourne);
      expect(moved.zoom, 10);
      expect(moved.tilt, 30);
      expect(camera.target, sydney, reason: 'original is immutable');
    });
  });

  group('ArxaKitMapMarker', () {
    test('kit.maps.models — identity is id + position + info window', () {
      const a = ArxaKitMapMarker(id: 'office', position: sydney, title: 'HQ');
      const b = ArxaKitMapMarker(id: 'office', position: sydney, title: 'HQ');
      expect(a, b);
      expect(a, isNot(const ArxaKitMapMarker(id: 'other', position: sydney)));
    });
  });

  group('ArxaKitMapConfig', () {
    test('kit.maps.models — defaults', () {
      const config =
          ArxaKitMapConfig(initialCameraPosition: ArxaKitCameraPosition(target: sydney));
      expect(config.markers, isEmpty);
      expect(config.mapType, ArxaKitMapType.normal);
      expect(config.myLocationEnabled, isFalse);
      expect(config.zoomControlsEnabled, isTrue);
      expect(config.compassEnabled, isTrue);
    });

    test('kit.maps.models — copyWith swaps markers without touching camera', () {
      const config =
          ArxaKitMapConfig(initialCameraPosition: ArxaKitCameraPosition(target: sydney));
      final updated = config.copyWith(
        markers: {const ArxaKitMapMarker(id: 'm1', position: melbourne)},
      );
      expect(updated.markers, hasLength(1));
      expect(updated.initialCameraPosition.target, sydney);
    });
  });
}
