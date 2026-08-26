import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_maps/arxa_kit_maps.dart';

void main() {
  group('arxaKitDefaultProviderFor', () {
    test('kit.maps.provider-resolution — iOS resolves to Apple Maps', () {
      final provider = arxaKitDefaultProviderFor(TargetPlatform.iOS);
      expect(provider, isA<ArxaKitAppleMapsProvider>());
      expect(provider.kind, ArxaKitMapProviderKind.apple);
    });

    test('kit.maps.provider-resolution — every non-iOS platform resolves to Google Maps', () {
      for (final platform in TargetPlatform.values
          .where((p) => p != TargetPlatform.iOS)) {
        final provider = arxaKitDefaultProviderFor(platform);
        expect(provider, isA<ArxaKitGoogleMapsProvider>(), reason: '$platform');
        expect(provider.kind, ArxaKitMapProviderKind.google);
      }
    });
  });

  group('tile providers', () {
    test('kit.maps.provider-resolution — ArxaKitOpenStreetMapProvider reports its kind', () {
      final provider =
          ArxaKitOpenStreetMapProvider(userAgentPackageName: 'com.example.test');
      expect(provider.kind, ArxaKitMapProviderKind.openStreetMap);
    });

    test('kit.maps.provider-resolution — ArxaKitMapboxProvider reports its kind', () {
      final provider = ArxaKitMapboxProvider(
        accessToken: 'pk.test',
        userAgentPackageName: 'com.example.test',
      );
      expect(provider.kind, ArxaKitMapProviderKind.mapbox);
    });
  });
}
