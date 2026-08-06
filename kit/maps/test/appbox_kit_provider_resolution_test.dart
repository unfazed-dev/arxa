import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_maps/appbox_kit_maps.dart';

void main() {
  group('appBoxKitDefaultProviderFor', () {
    test('kit.maps.provider-resolution — iOS resolves to Apple Maps', () {
      final provider = appBoxKitDefaultProviderFor(TargetPlatform.iOS);
      expect(provider, isA<AppBoxKitAppleMapsProvider>());
      expect(provider.kind, AppBoxKitMapProviderKind.apple);
    });

    test('kit.maps.provider-resolution — every non-iOS platform resolves to Google Maps', () {
      for (final platform in TargetPlatform.values
          .where((p) => p != TargetPlatform.iOS)) {
        final provider = appBoxKitDefaultProviderFor(platform);
        expect(provider, isA<AppBoxKitGoogleMapsProvider>(), reason: '$platform');
        expect(provider.kind, AppBoxKitMapProviderKind.google);
      }
    });
  });

  group('tile providers', () {
    test('kit.maps.provider-resolution — AppBoxKitOpenStreetMapProvider reports its kind', () {
      final provider =
          AppBoxKitOpenStreetMapProvider(userAgentPackageName: 'com.example.test');
      expect(provider.kind, AppBoxKitMapProviderKind.openStreetMap);
    });

    test('kit.maps.provider-resolution — AppBoxKitMapboxProvider reports its kind', () {
      final provider = AppBoxKitMapboxProvider(
        accessToken: 'pk.test',
        userAgentPackageName: 'com.example.test',
      );
      expect(provider.kind, AppBoxKitMapProviderKind.mapbox);
    });
  });
}
