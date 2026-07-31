import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import 'kit_bluetooth_adapter_state.dart';
import 'kit_bluetooth_capabilities.dart';
import 'kit_bluetooth_service.dart';

/// Production [KitBluetoothService] backed by `flutter_blue_plus`.
///
/// Native-first: `flutter_blue_plus` wraps CoreBluetooth (iOS) and
/// `android.bluetooth` (Android) directly. This adapter only re-projects its
/// adapter-state stream onto [KitBluetoothAdapterState] and gates
/// [requestEnable] on platform capability.
class FlutterBluePlusKitBluetoothService implements KitBluetoothService {
  FlutterBluePlusKitBluetoothService();

  @override
  KitBluetoothCapabilities get capabilities =>
      defaultTargetPlatform == TargetPlatform.android
          ? KitBluetoothCapabilities.androidDialog
          : KitBluetoothCapabilities.escortOnly;

  @override
  Stream<KitBluetoothAdapterState> get adapterState =>
      fbp.FlutterBluePlus.adapterState.map(_map);

  @override
  Future<KitBluetoothAdapterState> currentAdapterState() async =>
      _map(fbp.FlutterBluePlus.adapterStateNow);

  @override
  Future<void> requestEnable() async {
    if (!capabilities.canControlAdapter) {
      throw KitBluetoothUnsupportedError(
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

  KitBluetoothAdapterState _map(fbp.BluetoothAdapterState state) {
    switch (state) {
      case fbp.BluetoothAdapterState.unknown:
        return KitBluetoothAdapterState.unknown;
      case fbp.BluetoothAdapterState.unavailable:
        return KitBluetoothAdapterState.unavailable;
      case fbp.BluetoothAdapterState.unauthorized:
        return KitBluetoothAdapterState.unauthorized;
      case fbp.BluetoothAdapterState.turningOn:
        return KitBluetoothAdapterState.turningOn;
      case fbp.BluetoothAdapterState.on:
        return KitBluetoothAdapterState.poweredOn;
      case fbp.BluetoothAdapterState.turningOff:
        return KitBluetoothAdapterState.turningOff;
      case fbp.BluetoothAdapterState.off:
        return KitBluetoothAdapterState.poweredOff;
    }
  }
}
