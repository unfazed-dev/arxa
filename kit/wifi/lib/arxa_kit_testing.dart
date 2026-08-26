/// Scriptable test doubles for arxa_kit_wifi.
///
/// ```dart
/// final wifi = FakeArxaKitWifiService(initialState: ArxaKitWifiState.disconnected);
/// wifi.emit(ArxaKitWifiState.connected);          // drive the stream
/// wifi.setNetwork(const ArxaKitWifiNetwork(ssid: 'HomeWiFi'));
/// // requestEnable throws by default (adapter uncontrollable) → escort:
/// await wifi.openSettings();
/// expect(wifi.openSettingsCallCount, 1);
/// ```
library;

import 'dart:async';

import 'src/arxa_kit_wifi_capabilities.dart';
import 'src/arxa_kit_wifi_network.dart';
import 'src/arxa_kit_wifi_service.dart';
import 'src/arxa_kit_wifi_state.dart';

export 'src/arxa_kit_wifi_capabilities.dart';
export 'src/arxa_kit_wifi_network.dart';
export 'src/arxa_kit_wifi_service.dart';
export 'src/arxa_kit_wifi_state.dart';

/// An in-memory [ArxaKitWifiService] whose stream and readings are driven by the
/// test via [emit], [setNetwork] and [setState].
class FakeArxaKitWifiService implements ArxaKitWifiService {
  FakeArxaKitWifiService({
    ArxaKitWifiState initialState = ArxaKitWifiState.unknown,
    ArxaKitWifiNetwork? initialNetwork,
    this.capabilities = ArxaKitWifiCapabilities.escortOnly,
    this.settingsWillOpen = true,
  })  : _state = initialState,
        _network = initialNetwork;

  @override
  final ArxaKitWifiCapabilities capabilities;

  /// Value [openSettings] returns.
  final bool settingsWillOpen;

  final _controller = StreamController<ArxaKitWifiState>.broadcast();
  ArxaKitWifiState _state;
  ArxaKitWifiNetwork? _network;

  /// How many times [openSettings] was invoked.
  int openSettingsCallCount = 0;

  /// How many times [requestEnable] was invoked (even when it throws).
  int requestEnableCallCount = 0;

  /// Pushes [state] onto [stateChanges] and records it as the current state.
  void emit(ArxaKitWifiState state) {
    _state = state;
    _controller.add(state);
  }

  /// Sets the current state without emitting on the stream.
  void setState(ArxaKitWifiState state) => _state = state;

  /// Sets what [currentNetwork] returns.
  void setNetwork(ArxaKitWifiNetwork? network) => _network = network;

  @override
  Stream<ArxaKitWifiState> get stateChanges => _controller.stream;

  @override
  Future<ArxaKitWifiState> currentState() async => _state;

  @override
  Future<ArxaKitWifiNetwork?> currentNetwork() async => _network;

  @override
  Future<void> requestEnable() async {
    requestEnableCallCount++;
    if (!capabilities.canControlAdapter) {
      throw ArxaKitWifiUnsupportedError(
        'Fake: adapter control disabled by capabilities.',
      );
    }
    emit(ArxaKitWifiState.connected);
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCallCount++;
    return settingsWillOpen;
  }

  /// Releases the stream controller. Call in `tearDown`.
  Future<void> dispose() => _controller.close();
}
