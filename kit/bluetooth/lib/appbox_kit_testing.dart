/// Scriptable test doubles for appbox_kit_bluetooth.
///
/// ```dart
/// final bt = FakeAppBoxKitBluetoothService(
///   capabilities: AppBoxKitBluetoothCapabilities.androidDialog,
/// );
/// bt.emit(AppBoxKitBluetoothAdapterState.poweredOff);
/// await bt.requestEnable();               // flips to poweredOn on Android fake
/// expect(await bt.currentAdapterState(), AppBoxKitBluetoothAdapterState.poweredOn);
/// ```
library;

import 'dart:async';

import 'src/appbox_kit_bluetooth_adapter_state.dart';
import 'src/appbox_kit_bluetooth_capabilities.dart';
import 'src/appbox_kit_bluetooth_service.dart';

export 'src/appbox_kit_bluetooth_adapter_state.dart';
export 'src/appbox_kit_bluetooth_capabilities.dart';
export 'src/appbox_kit_bluetooth_service.dart';
export 'src/appbox_kit_bluetooth_device.dart';
export 'src/appbox_kit_bluetooth_scanner.dart';
export 'src/appbox_kit_bluetooth_gatt.dart';

/// An in-memory [AppBoxKitBluetoothService] whose adapter stream and capabilities
/// are driven by the test.
class FakeAppBoxKitBluetoothService implements AppBoxKitBluetoothService {
  FakeAppBoxKitBluetoothService({
    AppBoxKitBluetoothAdapterState initialState = AppBoxKitBluetoothAdapterState.unknown,
    this.capabilities = AppBoxKitBluetoothCapabilities.escortOnly,
    this.settingsWillOpen = true,
  }) : _state = initialState;

  @override
  final AppBoxKitBluetoothCapabilities capabilities;

  /// Value [openSettings] returns.
  final bool settingsWillOpen;

  final _controller =
      StreamController<AppBoxKitBluetoothAdapterState>.broadcast();
  AppBoxKitBluetoothAdapterState _state;

  /// How many times [openSettings] was invoked.
  int openSettingsCallCount = 0;

  /// How many times [requestEnable] was invoked (even when it throws).
  int requestEnableCallCount = 0;

  /// Pushes [state] onto [adapterState] and records it as current.
  void emit(AppBoxKitBluetoothAdapterState state) {
    _state = state;
    _controller.add(state);
  }

  @override
  Stream<AppBoxKitBluetoothAdapterState> get adapterState => _controller.stream;

  @override
  Future<AppBoxKitBluetoothAdapterState> currentAdapterState() async => _state;

  @override
  Future<void> requestEnable() async {
    requestEnableCallCount++;
    if (!capabilities.canControlAdapter) {
      throw AppBoxKitBluetoothUnsupportedError(
        'Fake: adapter control disabled by capabilities.',
      );
    }
    emit(AppBoxKitBluetoothAdapterState.poweredOn);
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCallCount++;
    return settingsWillOpen;
  }

  /// Releases the stream controller. Call in `tearDown`.
  Future<void> dispose() => _controller.close();
}
