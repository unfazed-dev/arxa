import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_bluetooth/testing.dart';

void main() {
  test('escort-only platform: requestEnable throws', () async {
    final bt = FakeKitBluetoothService(); // escortOnly by default
    await expectLater(
        bt.requestEnable(), throwsA(isA<KitBluetoothUnsupportedError>()));
    expect(bt.requestEnableCallCount, 1);
    expect(await bt.openSettings(), isTrue);
  });

  test('android platform: requestEnable powers the adapter on', () async {
    final bt = FakeKitBluetoothService(
      initialState: KitBluetoothAdapterState.poweredOff,
      capabilities: KitBluetoothCapabilities.androidDialog,
    );
    await bt.requestEnable();
    expect(await bt.currentAdapterState(), KitBluetoothAdapterState.poweredOn);
    await bt.dispose();
  });

  test('scanner + gatt stubs throw UnimplementedError', () {
    expect(() => const UnimplementedKitBluetoothScanner().stopScan(),
        throwsUnimplementedError);
    expect(() => const UnimplementedKitBluetoothGattClient().disconnect(),
        throwsUnimplementedError);
  });
}
