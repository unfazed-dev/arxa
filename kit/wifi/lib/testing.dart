/// Scriptable test doubles for appbox_kit_wifi.
///
/// ```dart
/// final wifi = FakeKitWifiService(initialState: KitWifiState.disconnected);
/// wifi.emit(KitWifiState.connected);          // drive the stream
/// wifi.setNetwork(const KitWifiNetwork(ssid: 'HomeWiFi'));
/// // requestEnable throws by default (adapter uncontrollable) → escort:
/// await wifi.openSettings();
/// expect(wifi.openSettingsCallCount, 1);
/// ```
library;

import 'dart:async';

import 'src/kit_wifi_capabilities.dart';
import 'src/kit_wifi_network.dart';
import 'src/kit_wifi_service.dart';
import 'src/kit_wifi_state.dart';

export 'src/kit_wifi_capabilities.dart';
export 'src/kit_wifi_network.dart';
export 'src/kit_wifi_service.dart';
export 'src/kit_wifi_state.dart';

/// An in-memory [KitWifiService] whose stream and readings are driven by the
/// test via [emit], [setNetwork] and [setState].
class FakeKitWifiService implements KitWifiService {
  FakeKitWifiService({
    KitWifiState initialState = KitWifiState.unknown,
    KitWifiNetwork? initialNetwork,
    this.capabilities = KitWifiCapabilities.escortOnly,
    this.settingsWillOpen = true,
  })  : _state = initialState,
        _network = initialNetwork;

  @override
  final KitWifiCapabilities capabilities;

  /// Value [openSettings] returns.
  final bool settingsWillOpen;

  final _controller = StreamController<KitWifiState>.broadcast();
  KitWifiState _state;
  KitWifiNetwork? _network;

  /// How many times [openSettings] was invoked.
  int openSettingsCallCount = 0;

  /// How many times [requestEnable] was invoked (even when it throws).
  int requestEnableCallCount = 0;

  /// Pushes [state] onto [stateChanges] and records it as the current state.
  void emit(KitWifiState state) {
    _state = state;
    _controller.add(state);
  }

  /// Sets the current state without emitting on the stream.
  void setState(KitWifiState state) => _state = state;

  /// Sets what [currentNetwork] returns.
  void setNetwork(KitWifiNetwork? network) => _network = network;

  @override
  Stream<KitWifiState> get stateChanges => _controller.stream;

  @override
  Future<KitWifiState> currentState() async => _state;

  @override
  Future<KitWifiNetwork?> currentNetwork() async => _network;

  @override
  Future<void> requestEnable() async {
    requestEnableCallCount++;
    if (!capabilities.canControlAdapter) {
      throw KitWifiUnsupportedError(
        'Fake: adapter control disabled by capabilities.',
      );
    }
    emit(KitWifiState.connected);
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCallCount++;
    return settingsWillOpen;
  }

  /// Releases the stream controller. Call in `tearDown`.
  Future<void> dispose() => _controller.close();
}
