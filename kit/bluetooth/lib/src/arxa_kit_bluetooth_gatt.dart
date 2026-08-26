import 'arxa_kit_bluetooth_device.dart';

/// Port for a GATT client — connect to a peripheral and read/write/subscribe
/// to its characteristics.
///
/// STUB (phase 2). The production binding will wrap `BluetoothDevice.connect`,
/// `discoverServices`, and `BluetoothCharacteristic.read/write/setNotifyValue`
/// from `flutter_blue_plus`. Signatures are final.
abstract interface class ArxaKitBluetoothGattClient {
  /// A live stream of the connection state for the active peripheral.
  Stream<ArxaKitBluetoothConnectionState> get connectionState;

  /// Connects to [device], optionally auto-reconnecting.
  Future<void> connect(ArxaKitBluetoothDevice device, {bool autoConnect});

  /// Disconnects from the active peripheral.
  Future<void> disconnect();

  /// Discovers the GATT services and characteristics of the connected device.
  Future<List<ArxaKitGattService>> discoverServices();

  /// Reads the current value of [characteristic].
  Future<List<int>> read(ArxaKitGattCharacteristic characteristic);

  /// Writes [value] to [characteristic]. When [withoutResponse] is true the
  /// peripheral does not acknowledge the write.
  Future<void> write(
    ArxaKitGattCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse,
  });

  /// Enables (or disables) notifications for [characteristic] and returns a
  /// stream of subsequent values.
  Stream<List<int>> setNotify(
    ArxaKitGattCharacteristic characteristic, {
    bool enable,
  });
}

/// Not-yet-implemented [ArxaKitBluetoothGattClient] — every method throws.
class UnimplementedArxaKitBluetoothGattClient implements ArxaKitBluetoothGattClient {
  const UnimplementedArxaKitBluetoothGattClient();

  // TODO(arxa_kit_bluetooth): implement over BluetoothDevice.connectionState.
  @override
  Stream<ArxaKitBluetoothConnectionState> get connectionState =>
      throw UnimplementedError('ArxaKitBluetoothGattClient.connectionState');

  // TODO(arxa_kit_bluetooth): implement over BluetoothDevice.connect.
  @override
  Future<void> connect(ArxaKitBluetoothDevice device, {bool autoConnect = false}) =>
      throw UnimplementedError('ArxaKitBluetoothGattClient.connect');

  // TODO(arxa_kit_bluetooth): implement over BluetoothDevice.disconnect.
  @override
  Future<void> disconnect() =>
      throw UnimplementedError('ArxaKitBluetoothGattClient.disconnect');

  // TODO(arxa_kit_bluetooth): implement over BluetoothDevice.discoverServices.
  @override
  Future<List<ArxaKitGattService>> discoverServices() =>
      throw UnimplementedError('ArxaKitBluetoothGattClient.discoverServices');

  // TODO(arxa_kit_bluetooth): implement over BluetoothCharacteristic.read.
  @override
  Future<List<int>> read(ArxaKitGattCharacteristic characteristic) =>
      throw UnimplementedError('ArxaKitBluetoothGattClient.read');

  // TODO(arxa_kit_bluetooth): implement over BluetoothCharacteristic.write.
  @override
  Future<void> write(
    ArxaKitGattCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse = false,
  }) =>
      throw UnimplementedError('ArxaKitBluetoothGattClient.write');

  // TODO(arxa_kit_bluetooth): implement over setNotifyValue + onValueReceived.
  @override
  Stream<List<int>> setNotify(
    ArxaKitGattCharacteristic characteristic, {
    bool enable = true,
  }) =>
      throw UnimplementedError('ArxaKitBluetoothGattClient.setNotify');
}
