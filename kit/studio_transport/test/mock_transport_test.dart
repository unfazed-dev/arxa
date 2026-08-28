import 'package:arxa_kit_studio_transport/arxa_kit_studio_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MockStudioSession', () {
    test('replays current status to a late subscriber, then transitions', () async {
      final mock = MockStudioSession();
      final seen = <StudioSessionStatus>[];
      final sub = mock.status.listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      mock.emit(StudioSessionStatus.connected, proxyPort: 8080);
      await Future<void>.delayed(Duration.zero);

      expect(seen, [
        StudioSessionStatus.connecting,
        StudioSessionStatus.connected,
      ]);
      await sub.cancel();
    });

    test('proxyPort is only set while connected', () {
      final mock = MockStudioSession();
      expect(mock.proxyPort, isNull);
      mock.emit(StudioSessionStatus.connected, proxyPort: 4242);
      expect(mock.proxyPort, 4242);
      mock.emit(StudioSessionStatus.reconnecting);
      expect(mock.proxyPort, isNull);
    });

    test('records push tokens in order', () async {
      final mock = MockStudioSession();
      await mock.registerPushToken('apns', 'tok-a');
      await mock.registerPushToken('fcm', 'tok-b');
      expect(mock.registeredPushTokens, [('apns', 'tok-a'), ('fcm', 'tok-b')]);
    });

    test('resume counts and moves to reconnecting', () async {
      final mock = MockStudioSession()
        ..emit(StudioSessionStatus.connected, proxyPort: 1);
      await mock.resume();
      expect(mock.resumeCount, 1);
      expect(mock.proxyPort, isNull);
    });

    test('resume is a no-op after revocation', () async {
      final mock = MockStudioSession()..emit(StudioSessionStatus.revoked);
      await mock.resume();
      // still revoked — a revoked pairing must never silently redial
      var latest = StudioSessionStatus.revoked;
      final sub = mock.status.listen((s) => latest = s);
      await Future<void>.delayed(Duration.zero);
      expect(latest, StudioSessionStatus.revoked);
      await sub.cancel();
    });

    test('close is terminal', () async {
      final mock = MockStudioSession();
      await mock.close();
      expect(mock.closed, isTrue);
      expect(await mock.status.first, StudioSessionStatus.disconnected);
    });
  });

  group('MockStudioTransport', () {
    test('hands out sessions and records payloads', () async {
      final factory = MockStudioTransport();
      final s1 = await factory.connect('arxa-pair:AAAA');
      final s2 = await factory.connect('arxa-pair:BBBB', deviceName: 'Test phone');
      expect(factory.connectedPayloads, ['arxa-pair:AAAA', 'arxa-pair:BBBB']);
      expect(factory.sessions, [s1, s2]);
    });
  });
}
