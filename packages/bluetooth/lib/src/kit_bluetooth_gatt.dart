import 'kit_bluetooth_device.dart';

/// Port for a GATT client — connect to a peripheral and read/write/subscribe
/// to its characteristics.
///
/// STUB (phase 2). The production binding will wrap `BluetoothDevice.connect`,
/// `discoverServices`, and `BluetoothCharacteristic.read/write/setNotifyValue`
/// from `flutter_blue_plus`. Signatures are final.
abstract interface class KitBluetoothGattClient {
  /// A live stream of the connection state for the active peripheral.
  Stream<KitBluetoothConnectionState> get connectionState;

  /// Connects to [device], optionally auto-reconnecting.
  Future<void> connect(KitBluetoothDevice device, {bool autoConnect});

  /// Disconnects from the active peripheral.
  Future<void> disconnect();

  /// Discovers the GATT services and characteristics of the connected device.
  Future<List<KitGattService>> discoverServices();

  /// Reads the current value of [characteristic].
  Future<List<int>> read(KitGattCharacteristic characteristic);

  /// Writes [value] to [characteristic]. When [withoutResponse] is true the
  /// peripheral does not acknowledge the write.
  Future<void> write(
    KitGattCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse,
  });

  /// Enables (or disables) notifications for [characteristic] and returns a
  /// stream of subsequent values.
  Stream<List<int>> setNotify(
    KitGattCharacteristic characteristic, {
    bool enable,
  });
}

/// Not-yet-implemented [KitBluetoothGattClient] — every method throws.
class UnimplementedKitBluetoothGattClient implements KitBluetoothGattClient {
  const UnimplementedKitBluetoothGattClient();

  // TODO(appbox_kit_bluetooth): implement over BluetoothDevice.connectionState.
  @override
  Stream<KitBluetoothConnectionState> get connectionState =>
      throw UnimplementedError('KitBluetoothGattClient.connectionState');

  // TODO(appbox_kit_bluetooth): implement over BluetoothDevice.connect.
  @override
  Future<void> connect(KitBluetoothDevice device, {bool autoConnect = false}) =>
      throw UnimplementedError('KitBluetoothGattClient.connect');

  // TODO(appbox_kit_bluetooth): implement over BluetoothDevice.disconnect.
  @override
  Future<void> disconnect() =>
      throw UnimplementedError('KitBluetoothGattClient.disconnect');

  // TODO(appbox_kit_bluetooth): implement over BluetoothDevice.discoverServices.
  @override
  Future<List<KitGattService>> discoverServices() =>
      throw UnimplementedError('KitBluetoothGattClient.discoverServices');

  // TODO(appbox_kit_bluetooth): implement over BluetoothCharacteristic.read.
  @override
  Future<List<int>> read(KitGattCharacteristic characteristic) =>
      throw UnimplementedError('KitBluetoothGattClient.read');

  // TODO(appbox_kit_bluetooth): implement over BluetoothCharacteristic.write.
  @override
  Future<void> write(
    KitGattCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse = false,
  }) =>
      throw UnimplementedError('KitBluetoothGattClient.write');

  // TODO(appbox_kit_bluetooth): implement over setNotifyValue + onValueReceived.
  @override
  Stream<List<int>> setNotify(
    KitGattCharacteristic characteristic, {
    bool enable = true,
  }) =>
      throw UnimplementedError('KitBluetoothGattClient.setNotify');
}
