import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_wifi/arxa_kit_testing.dart';

void main() {
  test('kit.wifi.escort — escort-only platform: requestEnable throws, UI falls back to settings',
      () async {
    final wifi = FakeArxaKitWifiService(); // escortOnly by default
    await expectLater(wifi.requestEnable(), throwsA(isA<ArxaKitWifiUnsupportedError>()));
    expect(wifi.requestEnableCallCount, 1);

    final opened = await wifi.openSettings();
    expect(opened, isTrue);
    expect(wifi.openSettingsCallCount, 1);
  });

  test('kit.wifi.state — stateChanges emits live OS-style state, not cached UI state', () async {
    final wifi = FakeArxaKitWifiService(initialState: ArxaKitWifiState.disconnected);
    expectLater(wifi.stateChanges, emitsInOrder([ArxaKitWifiState.connected]));
    wifi.emit(ArxaKitWifiState.connected);
    expect(await wifi.currentState(), ArxaKitWifiState.connected);
    await wifi.dispose();
  });
}
