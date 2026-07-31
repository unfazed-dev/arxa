import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_maps/appbox_kit_maps.dart';

void main() {
  const sydney = KitLatLng(-33.8688, 151.2093);
  const melbourne = KitLatLng(-37.8136, 144.9631);

  group('KitLatLng', () {
    test('value equality', () {
      expect(sydney, const KitLatLng(-33.8688, 151.2093));
      expect(sydney, isNot(melbourne));
      expect(sydney.hashCode, const KitLatLng(-33.8688, 151.2093).hashCode);
    });

    test('toString is readable', () {
      expect(sydney.toString(), 'KitLatLng(-33.8688, 151.2093)');
    });
  });

  group('KitLatLngBounds', () {
    test('value equality', () {
      const bounds =
          KitLatLngBounds(southwest: melbourne, northeast: sydney);
      expect(
        bounds,
        const KitLatLngBounds(southwest: melbourne, northeast: sydney),
      );
      expect(
        bounds,
        isNot(const KitLatLngBounds(southwest: sydney, northeast: sydney)),
      );
    });
  });

  group('KitCameraPosition', () {
    test('defaults and equality', () {
      const camera = KitCameraPosition(target: sydney);
      expect(camera.zoom, 14);
      expect(camera.bearing, 0);
      expect(camera.tilt, 0);
      expect(camera, const KitCameraPosition(target: sydney));
    });

    test('copyWith replaces only requested fields', () {
      const camera = KitCameraPosition(target: sydney, zoom: 10);
      final moved = camera.copyWith(target: melbourne, tilt: 30);
      expect(moved.target, melbourne);
      expect(moved.zoom, 10);
      expect(moved.tilt, 30);
      expect(camera.target, sydney, reason: 'original is immutable');
    });
  });

  group('KitMapMarker', () {
    test('identity is id + position + info window', () {
      const a = KitMapMarker(id: 'office', position: sydney, title: 'HQ');
      const b = KitMapMarker(id: 'office', position: sydney, title: 'HQ');
      expect(a, b);
      expect(a, isNot(const KitMapMarker(id: 'other', position: sydney)));
    });
  });

  group('KitMapConfig', () {
    test('defaults', () {
      const config =
          KitMapConfig(initialCameraPosition: KitCameraPosition(target: sydney));
      expect(config.markers, isEmpty);
      expect(config.mapType, KitMapType.normal);
      expect(config.myLocationEnabled, isFalse);
      expect(config.zoomControlsEnabled, isTrue);
      expect(config.compassEnabled, isTrue);
    });

    test('copyWith swaps markers without touching camera', () {
      const config =
          KitMapConfig(initialCameraPosition: KitCameraPosition(target: sydney));
      final updated = config.copyWith(
        markers: {const KitMapMarker(id: 'm1', position: melbourne)},
      );
      expect(updated.markers, hasLength(1));
      expect(updated.initialCameraPosition.target, sydney);
    });
  });
}
