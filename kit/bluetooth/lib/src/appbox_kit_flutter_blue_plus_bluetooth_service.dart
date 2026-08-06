import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import 'appbox_kit_bluetooth_adapter_state.dart';
import 'appbox_kit_bluetooth_capabilities.dart';
import 'appbox_kit_bluetooth_service.dart';

/// Production [AppBoxKitBluetoothService] backed by `flutter_blue_plus`.
///
/// Native-first: `flutter_blue_plus` wraps CoreBluetooth (iOS) and
/// `android.bluetooth` (Android) directly. This adapter only re-projects its
/// adapter-state stream onto [AppBoxKitBluetoothAdapterState] and gates
/// [requestEnable] on platform capability.
class AppBoxKitFlutterBluePlusBluetoothService implements AppBoxKitBluetoothService {
  AppBoxKitFlutterBluePlusBluetoothService();

  @override
  AppBoxKitBluetoothCapabilities get capabilities =>
      defaultTargetPlatform == TargetPlatform.android
          ? AppBoxKitBluetoothCapabilities.androidDialog
          : AppBoxKitBluetoothCapabilities.escortOnly;

  @override
  Stream<AppBoxKitBluetoothAdapterState> get adapterState =>
      fbp.FlutterBluePlus.adapterState.map(_map);

  @override
  Future<AppBoxKitBluetoothAdapterState> currentAdapterState() async =>
      _map(fbp.FlutterBluePlus.adapterStateNow);

  @override
  Future<void> requestEnable() async {
    if (!capabilities.canControlAdapter) {
      throw AppBoxKitBluetoothUnsupportedError(
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

  AppBoxKitBluetoothAdapterState _map(fbp.BluetoothAdapterState state) {
    switch (state) {
      case fbp.BluetoothAdapterState.unknown:
        return AppBoxKitBluetoothAdapterState.unknown;
      case fbp.BluetoothAdapterState.unavailable:
        return AppBoxKitBluetoothAdapterState.unavailable;
      case fbp.BluetoothAdapterState.unauthorized:
        return AppBoxKitBluetoothAdapterState.unauthorized;
      case fbp.BluetoothAdapterState.turningOn:
        return AppBoxKitBluetoothAdapterState.turningOn;
      case fbp.BluetoothAdapterState.on:
        return AppBoxKitBluetoothAdapterState.poweredOn;
      case fbp.BluetoothAdapterState.turningOff:
        return AppBoxKitBluetoothAdapterState.turningOff;
      case fbp.BluetoothAdapterState.off:
        return AppBoxKitBluetoothAdapterState.poweredOff;
    }
  }
}
