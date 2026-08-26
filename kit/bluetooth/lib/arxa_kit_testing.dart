/// Scriptable test doubles for arxa_kit_bluetooth.
///
/// ```dart
/// final bt = FakeArxaKitBluetoothService(
///   capabilities: ArxaKitBluetoothCapabilities.androidDialog,
/// );
/// bt.emit(ArxaKitBluetoothAdapterState.poweredOff);
/// await bt.requestEnable();               // flips to poweredOn on Android fake
/// expect(await bt.currentAdapterState(), ArxaKitBluetoothAdapterState.poweredOn);
/// ```
library;

import 'dart:async';

import 'src/arxa_kit_bluetooth_adapter_state.dart';
import 'src/arxa_kit_bluetooth_capabilities.dart';
import 'src/arxa_kit_bluetooth_service.dart';

export 'src/arxa_kit_bluetooth_adapter_state.dart';
export 'src/arxa_kit_bluetooth_capabilities.dart';
export 'src/arxa_kit_bluetooth_service.dart';
export 'src/arxa_kit_bluetooth_device.dart';
export 'src/arxa_kit_bluetooth_scanner.dart';
export 'src/arxa_kit_bluetooth_gatt.dart';

/// An in-memory [ArxaKitBluetoothService] whose adapter stream and capabilities
/// are driven by the test.
class FakeArxaKitBluetoothService implements ArxaKitBluetoothService {
  FakeArxaKitBluetoothService({
    ArxaKitBluetoothAdapterState initialState = ArxaKitBluetoothAdapterState.unknown,
    this.capabilities = ArxaKitBluetoothCapabilities.escortOnly,
    this.settingsWillOpen = true,
  }) : _state = initialState;

  @override
  final ArxaKitBluetoothCapabilities capabilities;

  /// Value [openSettings] returns.
  final bool settingsWillOpen;

  final _controller =
      StreamController<ArxaKitBluetoothAdapterState>.broadcast();
  ArxaKitBluetoothAdapterState _state;

  /// How many times [openSettings] was invoked.
  int openSettingsCallCount = 0;

  /// How many times [requestEnable] was invoked (even when it throws).
  int requestEnableCallCount = 0;

  /// Pushes [state] onto [adapterState] and records it as current.
  void emit(ArxaKitBluetoothAdapterState state) {
    _state = state;
    _controller.add(state);
  }

  @override
  Stream<ArxaKitBluetoothAdapterState> get adapterState => _controller.stream;

  @override
  Future<ArxaKitBluetoothAdapterState> currentAdapterState() async => _state;

  @override
  Future<void> requestEnable() async {
    requestEnableCallCount++;
    if (!capabilities.canControlAdapter) {
      throw ArxaKitBluetoothUnsupportedError(
        'Fake: adapter control disabled by capabilities.',
      );
    }
    emit(ArxaKitBluetoothAdapterState.poweredOn);
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCallCount++;
    return settingsWillOpen;
  }

  /// Releases the stream controller. Call in `tearDown`.
  Future<void> dispose() => _controller.close();
}
