import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_wifi/appbox_kit_testing.dart';

void main() {
  test('kit.wifi.escort — escort-only platform: requestEnable throws, UI falls back to settings',
      () async {
    final wifi = FakeAppBoxKitWifiService(); // escortOnly by default
    await expectLater(wifi.requestEnable(), throwsA(isA<AppBoxKitWifiUnsupportedError>()));
    expect(wifi.requestEnableCallCount, 1);

    final opened = await wifi.openSettings();
    expect(opened, isTrue);
    expect(wifi.openSettingsCallCount, 1);
  });

  test('kit.wifi.state — stateChanges emits live OS-style state, not cached UI state', () async {
    final wifi = FakeAppBoxKitWifiService(initialState: AppBoxKitWifiState.disconnected);
    expectLater(wifi.stateChanges, emitsInOrder([AppBoxKitWifiState.connected]));
    wifi.emit(AppBoxKitWifiState.connected);
    expect(await wifi.currentState(), AppBoxKitWifiState.connected);
    await wifi.dispose();
  });
}
