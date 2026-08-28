import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:arxa_studio_mobile/services/transport_service.dart';
import 'package:arxa_studio_mobile/ui/views/settings_shell/settings_home/settings_home_viewmodel.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('SettingsHomeViewModel', () {
    late FakeTransportService transport;
    late MockRouterService router;

    setUp(() {
      final s = registerTestServices();
      transport = s.transport;
      router = s.router;
    });
    tearDown(unregisterTestServices);

    test('unpair drops the connection and clears back to pairing', () async {
      await transport.beginPairing('ticket-1');
      final vm = SettingsHomeViewModel();
      await vm.unpair();
      expect(transport.current.state, ArxaConnectionState.notPaired);
      verify(() => router.clearStackAndShow(any())).called(1);
    });
  });
}
