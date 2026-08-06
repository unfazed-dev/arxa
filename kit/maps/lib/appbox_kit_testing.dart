/// Test doubles for appbox_kit_maps — import 'package:appbox_kit_maps/appbox_kit_testing.dart'.
library;

import 'package:flutter/widgets.dart';

import 'src/appbox_kit_map_provider.dart';
import 'src/models/appbox_kit_lat_lng.dart';
import 'src/models/appbox_kit_map_config.dart';

/// Records every camera call so tests can assert on map interaction without
/// any platform channel.
class RecordingAppBoxKitMapController implements AppBoxKitMapController {
  final List<AppBoxKitCameraPosition> movedCameras = <AppBoxKitCameraPosition>[];
  final List<AppBoxKitCameraPosition> animatedCameras = <AppBoxKitCameraPosition>[];

  @override
  Future<void> moveCamera(AppBoxKitCameraPosition position) async {
    movedCameras.add(position);
  }

  @override
  Future<void> animateCamera(AppBoxKitCameraPosition position) async {
    animatedCameras.add(position);
  }
}

/// In-memory [AppBoxKitMapProvider] that renders a plain [SizedBox], captures the
/// configs it was asked to build, and hands a [RecordingAppBoxKitMapController] to
/// `onMapCreated` synchronously.
class FakeAppBoxKitMapProvider implements AppBoxKitMapProvider {
  FakeAppBoxKitMapProvider({this.kind = AppBoxKitMapProviderKind.google});

  @override
  final AppBoxKitMapProviderKind kind;

  final List<AppBoxKitMapConfig> builtConfigs = <AppBoxKitMapConfig>[];
  final RecordingAppBoxKitMapController controller = RecordingAppBoxKitMapController();

  @override
  Widget buildMap({
    required AppBoxKitMapConfig config,
    AppBoxKitMapCreatedCallback? onMapCreated,
  }) {
    builtConfigs.add(config);
    onMapCreated?.call(controller);
    return const SizedBox.expand();
  }
}
