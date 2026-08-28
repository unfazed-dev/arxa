import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:arxa_studio_mobile/services/transport_service.dart';
import 'package:arxa_studio_mobile/ui/views/pairing_shell/pairing_scan/pairing_scan_viewmodel.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('PairingScanViewModel', () {
    late FakeTransportService transport;
    late MockRouterService router;

    setUp(() {
      final s = registerTestServices();
      transport = s.transport;
      router = s.router;
    });
    tearDown(unregisterTestServices);

    test('a scanned ticket begins pairing and navigates to connecting',
        () async {
      final vm = PairingScanViewModel();
      await vm.submitTicket('ticket-1');
      expect(transport.current.state, ArxaConnectionState.connected);
      verify(() => router.navigateTo(any())).called(1);
    });

    test('rapid duplicate detections submit only once', () async {
      final vm = PairingScanViewModel();
      final first = vm.submitTicket('ticket-1');
      final second = vm.submitTicket('ticket-1');
      await Future.wait([first, second]);
      verify(() => router.navigateTo(any())).called(1);
    });

    test('blank input is ignored', () async {
      final vm = PairingScanViewModel();
      await vm.submitTicket('   ');
      expect(transport.current.state, ArxaConnectionState.notPaired);
      verifyNever(() => router.navigateTo(any()));
    });
  });
}
