import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_wifi/testing.dart';

void main() {
  test('escort-only platform: requestEnable throws, UI falls back to settings',
      () async {
    final wifi = FakeKitWifiService(); // escortOnly by default
    await expectLater(wifi.requestEnable(), throwsA(isA<KitWifiUnsupportedError>()));
    expect(wifi.requestEnableCallCount, 1);

    final opened = await wifi.openSettings();
    expect(opened, isTrue);
    expect(wifi.openSettingsCallCount, 1);
  });

  test('stateChanges emits live OS-style state, not cached UI state', () async {
    final wifi = FakeKitWifiService(initialState: KitWifiState.disconnected);
    expectLater(wifi.stateChanges, emitsInOrder([KitWifiState.connected]));
    wifi.emit(KitWifiState.connected);
    expect(await wifi.currentState(), KitWifiState.connected);
    await wifi.dispose();
  });
}
