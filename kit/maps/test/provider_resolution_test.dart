import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_maps/appbox_kit_maps.dart';

void main() {
  group('defaultProviderFor', () {
    test('iOS resolves to Apple Maps', () {
      final provider = defaultProviderFor(TargetPlatform.iOS);
      expect(provider, isA<AppleMapsProvider>());
      expect(provider.kind, KitMapProviderKind.apple);
    });

    test('every non-iOS platform resolves to Google Maps', () {
      for (final platform in TargetPlatform.values
          .where((p) => p != TargetPlatform.iOS)) {
        final provider = defaultProviderFor(platform);
        expect(provider, isA<GoogleMapsProvider>(), reason: '$platform');
        expect(provider.kind, KitMapProviderKind.google);
      }
    });
  });

  group('stub providers', () {
    const config = KitMapConfig(
      initialCameraPosition:
          KitCameraPosition(target: KitLatLng(51.5074, -0.1278)),
    );

    test('OpenStreetMapProvider names flutter_map in its error', () {
      final stub = OpenStreetMapProvider();
      expect(stub.kind, KitMapProviderKind.openStreetMap);
      expect(
        () => stub.buildMap(config: config),
        throwsA(
          isA<UnimplementedError>().having(
            (e) => e.message,
            'message',
            contains('flutter_map'),
          ),
        ),
      );
    });

    test('MapboxProvider names mapbox_maps_flutter in its error', () {
      final stub = MapboxProvider();
      expect(stub.kind, KitMapProviderKind.mapbox);
      expect(
        () => stub.buildMap(config: config),
        throwsA(
          isA<UnimplementedError>().having(
            (e) => e.message,
            'message',
            contains('mapbox_maps_flutter'),
          ),
        ),
      );
    });
  });
}
