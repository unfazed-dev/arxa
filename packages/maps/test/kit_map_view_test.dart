import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_maps/appbox_kit_maps.dart';
import 'package:appbox_kit_maps/testing.dart';

void main() {
  const camera = KitCameraPosition(target: KitLatLng(40.7128, -74.006));
  const config = KitMapConfig(initialCameraPosition: camera);

  testWidgets('KitMapView builds through the injected provider',
      (tester) async {
    final fake = FakeMapProvider();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: KitMapView(config: config, provider: fake),
      ),
    );

    expect(fake.builtConfigs, hasLength(1));
    expect(fake.builtConfigs.single.initialCameraPosition, camera);
    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('onMapCreated receives a controller that records camera calls',
      (tester) async {
    final fake = FakeMapProvider();
    KitMapController? controller;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: KitMapView(
          config: config,
          provider: fake,
          onMapCreated: (c) => controller = c,
        ),
      ),
    );

    expect(controller, isNotNull);

    const moved = KitCameraPosition(target: KitLatLng(1, 2), zoom: 5);
    await controller!.moveCamera(moved);
    await controller!.animateCamera(camera);

    expect(fake.controller.movedCameras, [moved]);
    expect(fake.controller.animatedCameras, [camera]);
  });

  testWidgets('rebuilding with new markers hands the provider the new set',
      (tester) async {
    final fake = FakeMapProvider();
    const marker = KitMapMarker(id: 'pin', position: KitLatLng(3, 4));

    Widget build(KitMapConfig c) => Directionality(
          textDirection: TextDirection.ltr,
          child: KitMapView(config: c, provider: fake),
        );

    await tester.pumpWidget(build(config));
    await tester.pumpWidget(build(config.copyWith(markers: {marker})));

    expect(fake.builtConfigs, hasLength(2));
    expect(fake.builtConfigs.last.markers, {marker});
  });
}
