import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:appbox_kit_maps/appbox_kit_maps.dart';
import 'package:appbox_kit_maps/src/providers/tiled/appbox_kit_tiled_map_view.dart';

/// Serves an in-memory 1x1 transparent PNG for every tile — no HTTP.
class FakeAppBoxKitTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_transparentPng);

  static final Uint8List _transparentPng = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);
}

final _config = AppBoxKitMapConfig(
  initialCameraPosition: AppBoxKitCameraPosition(
    target: AppBoxKitLatLng(51.5074, -0.1278),
    zoom: 12,
  ),
  markers: {
    AppBoxKitMapMarker(id: 'london', position: AppBoxKitLatLng(51.5074, -0.1278)),
    AppBoxKitMapMarker(id: 'greenwich', position: AppBoxKitLatLng(51.4769, -0.0005)),
  },
);

Widget _host(Widget map) => MaterialApp(home: Scaffold(body: map));

void main() {
  group('AppBoxKitOpenStreetMapProvider', () {
    testWidgets('kit.maps.tiled-providers — builds a flutter_map with OSM tiles, UA, attribution, '
        'and the config camera/markers', (tester) async {
      final provider = AppBoxKitOpenStreetMapProvider(
        userAgentPackageName: 'com.example.test',
        tileProvider: FakeAppBoxKitTileProvider(),
      );

      await tester.pumpWidget(_host(provider.buildMap(config: _config)));

      expect(find.byType(FlutterMap), findsOneWidget);

      final tileLayer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(tileLayer.urlTemplate,
          'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
      // TileLayer injects the UA into the tile provider's headers.
      expect(
        tileLayer.tileProvider.headers['User-Agent'],
        'flutter_map (com.example.test)',
      );
      expect(tileLayer.tileDimension, 256);
      expect(appBoxKitTileProviderUsed(tester), isA<FakeAppBoxKitTileProvider>());

      expect(find.byType(SimpleAttributionWidget), findsOneWidget);

      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.options.initialCenter.latitude, 51.5074);
      expect(map.options.initialCenter.longitude, -0.1278);
      expect(map.options.initialZoom, 12);

      final markers = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
      expect(markers.markers, hasLength(2));
      expect(
        markers.markers.map((m) => m.point),
        containsAll([const LatLng(51.5074, -0.1278), const LatLng(51.4769, -0.0005)]),
      );
    });
  });

  group('AppBoxKitMapboxProvider', () {
    testWidgets('kit.maps.tiled-providers — builds Mapbox 512px raster tiles with the public token in '
        'the URL template', (tester) async {
      final provider = AppBoxKitMapboxProvider(
        accessToken: 'pk.test-token',
        userAgentPackageName: 'com.example.test',
        tileProvider: FakeAppBoxKitTileProvider(),
      );

      await tester.pumpWidget(_host(provider.buildMap(config: _config)));

      final tileLayer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(
        tileLayer.urlTemplate,
        'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/'
        '{z}/{x}/{y}@2x?access_token=pk.test-token',
      );
      expect(tileLayer.tileDimension, 512);
      expect(tileLayer.zoomOffset, -1);
      expect(
        tileLayer.tileProvider.headers['User-Agent'],
        'flutter_map (com.example.test)',
      );
      expect(find.byType(SimpleAttributionWidget), findsOneWidget);
    });

    testWidgets('kit.maps.tiled-providers — mapType selects the Mapbox style', (tester) async {
      final provider = AppBoxKitMapboxProvider(
        accessToken: 'pk.test-token',
        userAgentPackageName: 'com.example.test',
        tileProvider: FakeAppBoxKitTileProvider(),
      );

      String templateFor(AppBoxKitMapType type) {
        final map =
            provider.buildMap(config: _config.copyWith(mapType: type));
        return (map as AppBoxKitTiledMapView).urlTemplate;
      }

      expect(templateFor(AppBoxKitMapType.normal), contains('streets-v12'));
      expect(templateFor(AppBoxKitMapType.satellite), contains('satellite-v9'));
      expect(
        templateFor(AppBoxKitMapType.hybrid),
        contains('satellite-streets-v12'),
      );
      expect(templateFor(AppBoxKitMapType.terrain), contains('outdoors-v12'));
    });
  });

  group('AppBoxKitTiledMapView controller', () {
    testWidgets('kit.maps.tiled-providers — onMapCreated delivers a controller that moves the camera',
        (tester) async {
      final provider = AppBoxKitOpenStreetMapProvider(
        userAgentPackageName: 'com.example.test',
        tileProvider: FakeAppBoxKitTileProvider(),
      );
      AppBoxKitMapController? controller;

      await tester.pumpWidget(_host(provider.buildMap(
        config: _config,
        onMapCreated: (c) => controller = c,
      )));
      await tester.pump();

      expect(controller, isNotNull);

      await controller!.moveCamera(
        const AppBoxKitCameraPosition(target: AppBoxKitLatLng(48.8566, 2.3522), zoom: 9),
      );
      await tester.pump();

      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.mapController!.camera.center.latitude, closeTo(48.8566, 1e-9));
      expect(map.mapController!.camera.center.longitude, closeTo(2.3522, 1e-9));
      expect(map.mapController!.camera.zoom, 9);
    });
  });
}

TileProvider appBoxKitTileProviderUsed(WidgetTester tester) =>
    tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider;
