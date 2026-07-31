/// Scriptable test doubles for appbox_kit_bluetooth.
///
/// ```dart
/// final bt = FakeKitBluetoothService(
///   capabilities: KitBluetoothCapabilities.androidDialog,
/// );
/// bt.emit(KitBluetoothAdapterState.poweredOff);
/// await bt.requestEnable();               // flips to poweredOn on Android fake
/// expect(await bt.currentAdapterState(), KitBluetoothAdapterState.poweredOn);
/// ```
library;

import 'dart:async';

import 'src/kit_bluetooth_adapter_state.dart';
import 'src/kit_bluetooth_capabilities.dart';
import 'src/kit_bluetooth_service.dart';

export 'src/kit_bluetooth_adapter_state.dart';
export 'src/kit_bluetooth_capabilities.dart';
export 'src/kit_bluetooth_service.dart';
export 'src/kit_bluetooth_device.dart';
export 'src/kit_bluetooth_scanner.dart';
export 'src/kit_bluetooth_gatt.dart';

/// An in-memory [KitBluetoothService] whose adapter stream and capabilities
/// are driven by the test.
class FakeKitBluetoothService implements KitBluetoothService {
  FakeKitBluetoothService({
    KitBluetoothAdapterState initialState = KitBluetoothAdapterState.unknown,
    this.capabilities = KitBluetoothCapabilities.escortOnly,
    this.settingsWillOpen = true,
  }) : _state = initialState;

  @override
  final KitBluetoothCapabilities capabilities;

  /// Value [openSettings] returns.
  final bool settingsWillOpen;

  final _controller =
      StreamController<KitBluetoothAdapterState>.broadcast();
  KitBluetoothAdapterState _state;

  /// How many times [openSettings] was invoked.
  int openSettingsCallCount = 0;

  /// How many times [requestEnable] was invoked (even when it throws).
  int requestEnableCallCount = 0;

  /// Pushes [state] onto [adapterState] and records it as current.
  void emit(KitBluetoothAdapterState state) {
    _state = state;
    _controller.add(state);
  }

  @override
  Stream<KitBluetoothAdapterState> get adapterState => _controller.stream;

  @override
  Future<KitBluetoothAdapterState> currentAdapterState() async => _state;

  @override
  Future<void> requestEnable() async {
    requestEnableCallCount++;
    if (!capabilities.canControlAdapter) {
      throw KitBluetoothUnsupportedError(
        'Fake: adapter control disabled by capabilities.',
      );
    }
    emit(KitBluetoothAdapterState.poweredOn);
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCallCount++;
    return settingsWillOpen;
  }

  /// Releases the stream controller. Call in `tearDown`.
  Future<void> dispose() => _controller.close();
}
