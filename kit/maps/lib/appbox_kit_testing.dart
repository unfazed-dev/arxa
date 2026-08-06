/// Test doubles for appbox_kit_maps — import 'package:appbox_kit_maps/testing.dart'.
library;

import 'package:flutter/widgets.dart';

import 'src/kit_map_provider.dart';
import 'src/models/kit_lat_lng.dart';
import 'src/models/kit_map_config.dart';

/// Records every camera call so tests can assert on map interaction without
/// any platform channel.
class RecordingMapController implements KitMapController {
  final List<KitCameraPosition> movedCameras = <KitCameraPosition>[];
  final List<KitCameraPosition> animatedCameras = <KitCameraPosition>[];

  @override
  Future<void> moveCamera(KitCameraPosition position) async {
    movedCameras.add(position);
  }

  @override
  Future<void> animateCamera(KitCameraPosition position) async {
    animatedCameras.add(position);
  }
}

/// In-memory [KitMapProvider] that renders a plain [SizedBox], captures the
/// configs it was asked to build, and hands a [RecordingMapController] to
/// `onMapCreated` synchronously.
class FakeMapProvider implements KitMapProvider {
  FakeMapProvider({this.kind = KitMapProviderKind.google});

  @override
  final KitMapProviderKind kind;

  final List<KitMapConfig> builtConfigs = <KitMapConfig>[];
  final RecordingMapController controller = RecordingMapController();

  @override
  Widget buildMap({
    required KitMapConfig config,
    KitMapCreatedCallback? onMapCreated,
  }) {
    builtConfigs.add(config);
    onMapCreated?.call(controller);
    return const SizedBox.expand();
  }
}
