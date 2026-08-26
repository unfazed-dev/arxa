import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_bluetooth/arxa_kit_testing.dart';

void main() {
  test('kit.bluetooth.adapter-state — escort-only platform: requestEnable throws', () async {
    final bt = FakeArxaKitBluetoothService(); // escortOnly by default
    await expectLater(
        bt.requestEnable(), throwsA(isA<ArxaKitBluetoothUnsupportedError>()));
    expect(bt.requestEnableCallCount, 1);
    expect(await bt.openSettings(), isTrue);
  });

  test('kit.bluetooth.adapter-state — android platform: requestEnable powers the adapter on', () async {
    final bt = FakeArxaKitBluetoothService(
      initialState: ArxaKitBluetoothAdapterState.poweredOff,
      capabilities: ArxaKitBluetoothCapabilities.androidDialog,
    );
    await bt.requestEnable();
    expect(await bt.currentAdapterState(), ArxaKitBluetoothAdapterState.poweredOn);
    await bt.dispose();
  });

  test('kit.bluetooth.ble-stub — scanner + gatt stubs throw UnimplementedError', () {
    expect(() => const UnimplementedArxaKitBluetoothScanner().stopScan(),
        throwsUnimplementedError);
    expect(() => const UnimplementedArxaKitBluetoothGattClient().disconnect(),
        throwsUnimplementedError);
  });
}
