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

  group('tile providers', () {
    test('OpenStreetMapProvider reports its kind', () {
      final provider =
          OpenStreetMapProvider(userAgentPackageName: 'com.example.test');
      expect(provider.kind, KitMapProviderKind.openStreetMap);
    });

    test('MapboxProvider reports its kind', () {
      final provider = MapboxProvider(
        accessToken: 'pk.test',
        userAgentPackageName: 'com.example.test',
      );
      expect(provider.kind, KitMapProviderKind.mapbox);
    });
  });
}
