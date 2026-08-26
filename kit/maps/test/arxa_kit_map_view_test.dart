import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_maps/arxa_kit_maps.dart';
import 'package:arxa_kit_maps/arxa_kit_testing.dart';

void main() {
  const camera = ArxaKitCameraPosition(target: ArxaKitLatLng(40.7128, -74.006));
  const config = ArxaKitMapConfig(initialCameraPosition: camera);

  testWidgets('kit.maps.map-view — ArxaKitMapView builds through the injected provider',
      (tester) async {
    final fake = FakeArxaKitMapProvider();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ArxaKitMapView(config: config, provider: fake),
      ),
    );

    expect(fake.builtConfigs, hasLength(1));
    expect(fake.builtConfigs.single.initialCameraPosition, camera);
    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('kit.maps.map-view — onMapCreated receives a controller that records camera calls',
      (tester) async {
    final fake = FakeArxaKitMapProvider();
    ArxaKitMapController? controller;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ArxaKitMapView(
          config: config,
          provider: fake,
          onMapCreated: (c) => controller = c,
        ),
      ),
    );

    expect(controller, isNotNull);

    const moved = ArxaKitCameraPosition(target: ArxaKitLatLng(1, 2), zoom: 5);
    await controller!.moveCamera(moved);
    await controller!.animateCamera(camera);

    expect(fake.controller.movedCameras, [moved]);
    expect(fake.controller.animatedCameras, [camera]);
  });

  testWidgets('kit.maps.map-view — rebuilding with new markers hands the provider the new set',
      (tester) async {
    final fake = FakeArxaKitMapProvider();
    const marker = ArxaKitMapMarker(id: 'pin', position: ArxaKitLatLng(3, 4));

    Widget build(ArxaKitMapConfig c) => Directionality(
          textDirection: TextDirection.ltr,
          child: ArxaKitMapView(config: c, provider: fake),
        );

    await tester.pumpWidget(build(config));
    await tester.pumpWidget(build(config.copyWith(markers: {marker})));

    expect(fake.builtConfigs, hasLength(2));
    expect(fake.builtConfigs.last.markers, {marker});
  });
}
