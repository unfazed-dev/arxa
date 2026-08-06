/// A discovered Bluetooth (BLE) peripheral.
///
/// Value object shared by the scanner and GATT ports. Plugin-neutral: no
/// `flutter_blue_plus` types leak through.
class AppBoxKitBluetoothDevice {
  const AppBoxKitBluetoothDevice({
    required this.id,
    this.name,
  });

  /// Stable per-scan device identifier (iOS UUID / Android MAC).
  final String id;

  /// Advertised device name, if any.
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitBluetoothDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'AppBoxKitBluetoothDevice($id, name: $name)';
}

/// One advertisement observed during a scan.
class AppBoxKitBluetoothScanResult {
  const AppBoxKitBluetoothScanResult({
    required this.device,
    required this.rssi,
  });

  /// The advertising peripheral.
  final AppBoxKitBluetoothDevice device;

  /// Received signal strength in dBm (negative; closer to 0 is stronger).
  final int rssi;
}

/// The connection state of a GATT client.
enum AppBoxKitBluetoothConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

/// A discovered GATT service on a connected peripheral.
class AppBoxKitGattService {
  const AppBoxKitGattService({
    required this.uuid,
    required this.characteristics,
  });

  /// Service UUID (128-bit canonical string form).
  final String uuid;

  /// Characteristics exposed by this service.
  final List<AppBoxKitGattCharacteristic> characteristics;
}

/// A discovered GATT characteristic.
class AppBoxKitGattCharacteristic {
  const AppBoxKitGattCharacteristic({
    required this.serviceUuid,
    required this.uuid,
  });

  /// UUID of the owning service.
  final String serviceUuid;

  /// Characteristic UUID (128-bit canonical string form).
  final String uuid;
}
