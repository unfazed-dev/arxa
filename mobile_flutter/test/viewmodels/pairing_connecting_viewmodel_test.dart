import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:arxa_studio_mobile/services/transport_service.dart';
import 'package:arxa_studio_mobile/ui/views/pairing_shell/pairing_connecting/pairing_connecting_viewmodel.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('PairingConnectingViewModel', () {
    late FakeTransportService transport;
    late MockRouterService router;

    setUp(() {
      final s = registerTestServices();
      transport = s.transport;
      router = s.router;
    });
    tearDown(unregisterTestServices);

    test('hands off to push permission exactly once on connected', () async {
      final vm = PairingConnectingViewModel()..start();
      await transport.beginPairing('ticket-1');
      await Future<void>.delayed(Duration.zero);
      expect(vm.state, ArxaConnectionState.connected);
      verify(() => router.replaceWith(any())).called(1);
      vm.dispose();
    });

    test('surfaces the transport error', () async {
      final vm = PairingConnectingViewModel()..start();
      await transport.beginPairing('');
      await Future<void>.delayed(Duration.zero);
      expect(vm.connectionError, isNotNull);
      verifyNever(() => router.replaceWith(any()));
      vm.dispose();
    });
  });
}
