import 'appbox_kit_bluetooth_device.dart';

/// Port for a GATT client — connect to a peripheral and read/write/subscribe
/// to its characteristics.
///
/// STUB (phase 2). The production binding will wrap `BluetoothDevice.connect`,
/// `discoverServices`, and `BluetoothCharacteristic.read/write/setNotifyValue`
/// from `flutter_blue_plus`. Signatures are final.
abstract interface class AppBoxKitBluetoothGattClient {
  /// A live stream of the connection state for the active peripheral.
  Stream<AppBoxKitBluetoothConnectionState> get connectionState;

  /// Connects to [device], optionally auto-reconnecting.
  Future<void> connect(AppBoxKitBluetoothDevice device, {bool autoConnect});

  /// Disconnects from the active peripheral.
  Future<void> disconnect();

  /// Discovers the GATT services and characteristics of the connected device.
  Future<List<AppBoxKitGattService>> discoverServices();

  /// Reads the current value of [characteristic].
  Future<List<int>> read(AppBoxKitGattCharacteristic characteristic);

  /// Writes [value] to [characteristic]. When [withoutResponse] is true the
  /// peripheral does not acknowledge the write.
  Future<void> write(
    AppBoxKitGattCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse,
  });

  /// Enables (or disables) notifications for [characteristic] and returns a
  /// stream of subsequent values.
  Stream<List<int>> setNotify(
    AppBoxKitGattCharacteristic characteristic, {
    bool enable,
  });
}

/// Not-yet-implemented [AppBoxKitBluetoothGattClient] — every method throws.
class UnimplementedAppBoxKitBluetoothGattClient implements AppBoxKitBluetoothGattClient {
  const UnimplementedAppBoxKitBluetoothGattClient();

  // TODO(appbox_kit_bluetooth): implement over BluetoothDevice.connectionState.
  @override
  Stream<AppBoxKitBluetoothConnectionState> get connectionState =>
      throw UnimplementedError('AppBoxKitBluetoothGattClient.connectionState');

  // TODO(appbox_kit_bluetooth): implement over BluetoothDevice.connect.
  @override
  Future<void> connect(AppBoxKitBluetoothDevice device, {bool autoConnect = false}) =>
      throw UnimplementedError('AppBoxKitBluetoothGattClient.connect');

  // TODO(appbox_kit_bluetooth): implement over BluetoothDevice.disconnect.
  @override
  Future<void> disconnect() =>
      throw UnimplementedError('AppBoxKitBluetoothGattClient.disconnect');

  // TODO(appbox_kit_bluetooth): implement over BluetoothDevice.discoverServices.
  @override
  Future<List<AppBoxKitGattService>> discoverServices() =>
      throw UnimplementedError('AppBoxKitBluetoothGattClient.discoverServices');

  // TODO(appbox_kit_bluetooth): implement over BluetoothCharacteristic.read.
  @override
  Future<List<int>> read(AppBoxKitGattCharacteristic characteristic) =>
      throw UnimplementedError('AppBoxKitBluetoothGattClient.read');

  // TODO(appbox_kit_bluetooth): implement over BluetoothCharacteristic.write.
  @override
  Future<void> write(
    AppBoxKitGattCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse = false,
  }) =>
      throw UnimplementedError('AppBoxKitBluetoothGattClient.write');

  // TODO(appbox_kit_bluetooth): implement over setNotifyValue + onValueReceived.
  @override
  Stream<List<int>> setNotify(
    AppBoxKitGattCharacteristic characteristic, {
    bool enable = true,
  }) =>
      throw UnimplementedError('AppBoxKitBluetoothGattClient.setNotify');
}
