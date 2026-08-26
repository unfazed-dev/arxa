import 'arxa_kit_bluetooth_device.dart';

/// Port for BLE scanning.
///
/// STUB (phase 2). The production binding will wrap
/// `FlutterBluePlus.startScan` / `scanResults` / `stopScan`. Signatures are
/// final so consumers can code against them today.
abstract interface class ArxaKitBluetoothScanner {
  /// A live stream of scan results while a scan is active.
  Stream<List<ArxaKitBluetoothScanResult>> get scanResults;

  /// Whether a scan is currently running.
  Stream<bool> get isScanning;

  /// Starts a scan, optionally filtered to peripherals advertising any of
  /// [withServiceUuids], for at most [timeout].
  Future<void> startScan({
    List<String> withServiceUuids,
    Duration? timeout,
  });

  /// Stops an in-progress scan.
  Future<void> stopScan();
}

/// Not-yet-implemented [ArxaKitBluetoothScanner] — every method throws so callers
/// fail loudly rather than silently no-op.
class UnimplementedArxaKitBluetoothScanner implements ArxaKitBluetoothScanner {
  const UnimplementedArxaKitBluetoothScanner();

  // TODO(arxa_kit_bluetooth): implement over FlutterBluePlus.scanResults.
  @override
  Stream<List<ArxaKitBluetoothScanResult>> get scanResults =>
      throw UnimplementedError('ArxaKitBluetoothScanner.scanResults');

  // TODO(arxa_kit_bluetooth): implement over FlutterBluePlus.isScanning.
  @override
  Stream<bool> get isScanning =>
      throw UnimplementedError('ArxaKitBluetoothScanner.isScanning');

  // TODO(arxa_kit_bluetooth): implement over FlutterBluePlus.startScan.
  @override
  Future<void> startScan({
    List<String> withServiceUuids = const [],
    Duration? timeout,
  }) =>
      throw UnimplementedError('ArxaKitBluetoothScanner.startScan');

  // TODO(arxa_kit_bluetooth): implement over FlutterBluePlus.stopScan.
  @override
  Future<void> stopScan() =>
      throw UnimplementedError('ArxaKitBluetoothScanner.stopScan');
}
