import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import 'arxa_kit_bluetooth_adapter_state.dart';
import 'arxa_kit_bluetooth_capabilities.dart';
import 'arxa_kit_bluetooth_service.dart';

/// Production [ArxaKitBluetoothService] backed by `flutter_blue_plus`.
///
/// Native-first: `flutter_blue_plus` wraps CoreBluetooth (iOS) and
/// `android.bluetooth` (Android) directly. This adapter only re-projects its
/// adapter-state stream onto [ArxaKitBluetoothAdapterState] and gates
/// [requestEnable] on platform capability.
class ArxaKitFlutterBluePlusBluetoothService implements ArxaKitBluetoothService {
  ArxaKitFlutterBluePlusBluetoothService();

  @override
  ArxaKitBluetoothCapabilities get capabilities =>
      defaultTargetPlatform == TargetPlatform.android
          ? ArxaKitBluetoothCapabilities.androidDialog
          : ArxaKitBluetoothCapabilities.escortOnly;

  @override
  Stream<ArxaKitBluetoothAdapterState> get adapterState =>
      fbp.FlutterBluePlus.adapterState.map(_map);

  @override
  Future<ArxaKitBluetoothAdapterState> currentAdapterState() async =>
      _map(fbp.FlutterBluePlus.adapterStateNow);

  @override
  Future<void> requestEnable() async {
    if (!capabilities.canControlAdapter) {
      throw ArxaKitBluetoothUnsupportedError(
        'Enabling Bluetooth programmatically is not supported on this '
        'platform; call openSettings() to escort the user instead.',
      );
    }
    // Android: shows the system BluetoothAdapter.ACTION_REQUEST_ENABLE dialog.
    await fbp.FlutterBluePlus.turnOn();
  }

  @override
  Future<bool> openSettings() async {
    await AppSettings.openAppSettings(type: AppSettingsType.bluetooth);
    return true;
  }

  ArxaKitBluetoothAdapterState _map(fbp.BluetoothAdapterState state) {
    switch (state) {
      case fbp.BluetoothAdapterState.unknown:
        return ArxaKitBluetoothAdapterState.unknown;
      case fbp.BluetoothAdapterState.unavailable:
        return ArxaKitBluetoothAdapterState.unavailable;
      case fbp.BluetoothAdapterState.unauthorized:
        return ArxaKitBluetoothAdapterState.unauthorized;
      case fbp.BluetoothAdapterState.turningOn:
        return ArxaKitBluetoothAdapterState.turningOn;
      case fbp.BluetoothAdapterState.on:
        return ArxaKitBluetoothAdapterState.poweredOn;
      case fbp.BluetoothAdapterState.turningOff:
        return ArxaKitBluetoothAdapterState.turningOff;
      case fbp.BluetoothAdapterState.off:
        return ArxaKitBluetoothAdapterState.poweredOff;
    }
  }
}
