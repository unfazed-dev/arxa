/// A discovered Bluetooth (BLE) peripheral.
///
/// Value object shared by the scanner and GATT ports. Plugin-neutral: no
/// `flutter_blue_plus` types leak through.
class KitBluetoothDevice {
  const KitBluetoothDevice({
    required this.id,
    this.name,
  });

  /// Stable per-scan device identifier (iOS UUID / Android MAC).
  final String id;

  /// Advertised device name, if any.
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is KitBluetoothDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'KitBluetoothDevice($id, name: $name)';
}

/// One advertisement observed during a scan.
class KitBluetoothScanResult {
  const KitBluetoothScanResult({
    required this.device,
    required this.rssi,
  });

  /// The advertising peripheral.
  final KitBluetoothDevice device;

  /// Received signal strength in dBm (negative; closer to 0 is stronger).
  final int rssi;
}

/// The connection state of a GATT client.
enum KitBluetoothConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

/// A discovered GATT service on a connected peripheral.
class KitGattService {
  const KitGattService({
    required this.uuid,
    required this.characteristics,
  });

  /// Service UUID (128-bit canonical string form).
  final String uuid;

  /// Characteristics exposed by this service.
  final List<KitGattCharacteristic> characteristics;
}

/// A discovered GATT characteristic.
class KitGattCharacteristic {
  const KitGattCharacteristic({
    required this.serviceUuid,
    required this.uuid,
  });

  /// UUID of the owning service.
  final String serviceUuid;

  /// Characteristic UUID (128-bit canonical string form).
  final String uuid;
}
