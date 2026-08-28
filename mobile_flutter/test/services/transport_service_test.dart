import 'package:flutter_test/flutter_test.dart';

import 'package:arxa_studio_mobile/services/transport_service.dart';

void main() {
  group('FakeTransportService', () {
    test('walks pairing -> connecting -> connected and serves the loopback URL',
        () async {
      final t = FakeTransportService(port: 4567);
      final seen = <ArxaConnectionState>[];
      final sub = t.status.listen((s) => seen.add(s.state));
      await t.beginPairing('ticket-1');
      await Future<void>.delayed(Duration.zero); // let the stream deliver
      expect(seen, [
        ArxaConnectionState.pairing,
        ArxaConnectionState.connecting,
        ArxaConnectionState.connected,
      ]);
      expect(t.current.studioUrl, Uri.parse('http://127.0.0.1:4567/'));
      await sub.cancel();
      await t.dispose();
    });

    test('rejects an empty ticket without leaving notPaired', () async {
      final t = FakeTransportService();
      await t.beginPairing('   ');
      expect(t.current.state, ArxaConnectionState.notPaired);
      expect(t.current.error, isNotNull);
      await t.dispose();
    });

    test('unpair returns to notPaired and drops the studio URL', () async {
      final t = FakeTransportService();
      await t.beginPairing('ticket-1');
      await t.unpair();
      expect(t.current.state, ArxaConnectionState.notPaired);
      expect(t.current.studioUrl, isNull);
      await t.dispose();
    });

    test('records the forwarded push token', () async {
      final t = FakeTransportService();
      await t.setPushToken('ios', 'tok-1');
      expect(t.lastPushToken, ('ios', 'tok-1'));
      await t.dispose();
    });
  });
}
