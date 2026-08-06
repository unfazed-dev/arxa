/// Scriptable test doubles for appbox_kit_wifi.
///
/// ```dart
/// final wifi = FakeAppBoxKitWifiService(initialState: AppBoxKitWifiState.disconnected);
/// wifi.emit(AppBoxKitWifiState.connected);          // drive the stream
/// wifi.setNetwork(const AppBoxKitWifiNetwork(ssid: 'HomeWiFi'));
/// // requestEnable throws by default (adapter uncontrollable) → escort:
/// await wifi.openSettings();
/// expect(wifi.openSettingsCallCount, 1);
/// ```
library;

import 'dart:async';

import 'src/appbox_kit_wifi_capabilities.dart';
import 'src/appbox_kit_wifi_network.dart';
import 'src/appbox_kit_wifi_service.dart';
import 'src/appbox_kit_wifi_state.dart';

export 'src/appbox_kit_wifi_capabilities.dart';
export 'src/appbox_kit_wifi_network.dart';
export 'src/appbox_kit_wifi_service.dart';
export 'src/appbox_kit_wifi_state.dart';

/// An in-memory [AppBoxKitWifiService] whose stream and readings are driven by the
/// test via [emit], [setNetwork] and [setState].
class FakeAppBoxKitWifiService implements AppBoxKitWifiService {
  FakeAppBoxKitWifiService({
    AppBoxKitWifiState initialState = AppBoxKitWifiState.unknown,
    AppBoxKitWifiNetwork? initialNetwork,
    this.capabilities = AppBoxKitWifiCapabilities.escortOnly,
    this.settingsWillOpen = true,
  })  : _state = initialState,
        _network = initialNetwork;

  @override
  final AppBoxKitWifiCapabilities capabilities;

  /// Value [openSettings] returns.
  final bool settingsWillOpen;

  final _controller = StreamController<AppBoxKitWifiState>.broadcast();
  AppBoxKitWifiState _state;
  AppBoxKitWifiNetwork? _network;

  /// How many times [openSettings] was invoked.
  int openSettingsCallCount = 0;

  /// How many times [requestEnable] was invoked (even when it throws).
  int requestEnableCallCount = 0;

  /// Pushes [state] onto [stateChanges] and records it as the current state.
  void emit(AppBoxKitWifiState state) {
    _state = state;
    _controller.add(state);
  }

  /// Sets the current state without emitting on the stream.
  void setState(AppBoxKitWifiState state) => _state = state;

  /// Sets what [currentNetwork] returns.
  void setNetwork(AppBoxKitWifiNetwork? network) => _network = network;

  @override
  Stream<AppBoxKitWifiState> get stateChanges => _controller.stream;

  @override
  Future<AppBoxKitWifiState> currentState() async => _state;

  @override
  Future<AppBoxKitWifiNetwork?> currentNetwork() async => _network;

  @override
  Future<void> requestEnable() async {
    requestEnableCallCount++;
    if (!capabilities.canControlAdapter) {
      throw AppBoxKitWifiUnsupportedError(
        'Fake: adapter control disabled by capabilities.',
      );
    }
    emit(AppBoxKitWifiState.connected);
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCallCount++;
    return settingsWillOpen;
  }

  /// Releases the stream controller. Call in `tearDown`.
  Future<void> dispose() => _controller.close();
}
