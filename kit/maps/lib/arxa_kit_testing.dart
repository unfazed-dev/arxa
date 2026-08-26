/// Test doubles for arxa_kit_maps — import 'package:arxa_kit_maps/arxa_kit_testing.dart'.
library;

import 'package:flutter/widgets.dart';

import 'src/arxa_kit_map_provider.dart';
import 'src/models/arxa_kit_lat_lng.dart';
import 'src/models/arxa_kit_map_config.dart';

/// Records every camera call so tests can assert on map interaction without
/// any platform channel.
class RecordingArxaKitMapController implements ArxaKitMapController {
  final List<ArxaKitCameraPosition> movedCameras = <ArxaKitCameraPosition>[];
  final List<ArxaKitCameraPosition> animatedCameras = <ArxaKitCameraPosition>[];

  @override
  Future<void> moveCamera(ArxaKitCameraPosition position) async {
    movedCameras.add(position);
  }

  @override
  Future<void> animateCamera(ArxaKitCameraPosition position) async {
    animatedCameras.add(position);
  }
}

/// In-memory [ArxaKitMapProvider] that renders a plain [SizedBox], captures the
/// configs it was asked to build, and hands a [RecordingArxaKitMapController] to
/// `onMapCreated` synchronously.
class FakeArxaKitMapProvider implements ArxaKitMapProvider {
  FakeArxaKitMapProvider({this.kind = ArxaKitMapProviderKind.google});

  @override
  final ArxaKitMapProviderKind kind;

  final List<ArxaKitMapConfig> builtConfigs = <ArxaKitMapConfig>[];
  final RecordingArxaKitMapController controller = RecordingArxaKitMapController();

  @override
  Widget buildMap({
    required ArxaKitMapConfig config,
    ArxaKitMapCreatedCallback? onMapCreated,
  }) {
    builtConfigs.add(config);
    onMapCreated?.call(controller);
    return const SizedBox.expand();
  }
}
