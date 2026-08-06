import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_bluetooth/appbox_kit_testing.dart';

void main() {
  test('escort-only platform: requestEnable throws', () async {
    final bt = FakeAppBoxKitBluetoothService(); // escortOnly by default
    await expectLater(
        bt.requestEnable(), throwsA(isA<AppBoxKitBluetoothUnsupportedError>()));
    expect(bt.requestEnableCallCount, 1);
    expect(await bt.openSettings(), isTrue);
  });

  test('android platform: requestEnable powers the adapter on', () async {
    final bt = FakeAppBoxKitBluetoothService(
      initialState: AppBoxKitBluetoothAdapterState.poweredOff,
      capabilities: AppBoxKitBluetoothCapabilities.androidDialog,
    );
    await bt.requestEnable();
    expect(await bt.currentAdapterState(), AppBoxKitBluetoothAdapterState.poweredOn);
    await bt.dispose();
  });

  test('scanner + gatt stubs throw UnimplementedError', () {
    expect(() => const UnimplementedAppBoxKitBluetoothScanner().stopScan(),
        throwsUnimplementedError);
    expect(() => const UnimplementedAppBoxKitBluetoothGattClient().disconnect(),
        throwsUnimplementedError);
  });
}
