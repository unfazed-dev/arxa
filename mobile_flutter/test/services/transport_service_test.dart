import 'package:arxa_kit_studio_transport/arxa_kit_studio_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arxa_studio_mobile/services/iroh_transport_service.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';

/// Let queued microtasks/stream events deliver.
Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('IrohTransportService (over MockStudioTransport — no network)', () {
    late MockStudioTransport mock;
    late IrohTransportService t;
    late List<ArxaConnectionStatus> seen;

    setUp(() {
      mock = MockStudioTransport();
      t = IrohTransportService(connect: mock.connect, deviceName: 'test-phone');
      seen = [];
      t.status.listen(seen.add);
    });

    tearDown(() => t.dispose());

    test('beginPairing walks pairing -> connecting -> connected and exposes '
        'the loopback proxy URL from the session port', () async {
      await t.beginPairing('arxa-pair:abc');
      await pump();
      expect(mock.connectedPayloads, ['arxa-pair:abc']);
      mock.sessions.single.emit(StudioSessionStatus.connected, proxyPort: 8080);
      await pump();
      expect(seen.map((s) => s.state), [
        ArxaConnectionState.pairing,
        ArxaConnectionState.connecting, // session replays connecting on listen
        ArxaConnectionState.connected,
      ]);
      expect(t.current.studioUrl, Uri.parse('http://127.0.0.1:8080/'));
    });

    test(
      'reconnecting maps back to connecting and drops the studio URL',
      () async {
        await t.beginPairing('arxa-pair:abc');
        await pump();
        final session = mock.sessions.single;
        session.emit(StudioSessionStatus.connected, proxyPort: 8080);
        await pump();
        session.emit(StudioSessionStatus.reconnecting);
        await pump();
        expect(t.current.state, ArxaConnectionState.connecting);
        expect(t.current.studioUrl, isNull);
      },
    );

    test('revoked maps to notPaired with an error', () async {
      await t.beginPairing('arxa-pair:abc');
      await pump();
      mock.sessions.single.emit(StudioSessionStatus.revoked);
      await pump();
      expect(t.current.state, ArxaConnectionState.notPaired);
      expect(t.current.error, contains('revoked'));
    });

    test('rejects an empty ticket without dialing', () async {
      await t.beginPairing('   ');
      expect(t.current.state, ArxaConnectionState.notPaired);
      expect(t.current.error, isNotNull);
      expect(mock.connectedPayloads, isEmpty);
    });

    test('a malformed pairing code surfaces as notPaired + error', () async {
      final failing = IrohTransportService(
        connect: (payload, {deviceName}) =>
            throw const FormatException('bad payload'),
      );
      await failing.beginPairing('not-a-ticket');
      expect(failing.current.state, ArxaConnectionState.notPaired);
      expect(failing.current.error, 'bad payload');
      await failing.dispose();
    });

    test('push token set while live is handed to the session exactly once '
        '(transport re-sends per-connection itself)', () async {
      await t.beginPairing('arxa-pair:abc');
      await pump();
      final session = mock.sessions.single;
      await t.setPushToken('apns', 'tok-1');
      expect(session.registeredPushTokens, [('apns', 'tok-1')]);
      // Reconnects are the transport's job — the service must NOT re-send.
      session.emit(StudioSessionStatus.reconnecting);
      session.emit(StudioSessionStatus.connected, proxyPort: 9000);
      await pump();
      expect(session.registeredPushTokens, [('apns', 'tok-1')]);
    });

    test(
      'stored push token is re-handed to each new session after re-pair',
      () async {
        await t.setPushToken('fcm', 'tok-2'); // before any session: stored only
        await t.beginPairing('arxa-pair:first');
        await pump();
        expect(mock.sessions[0].registeredPushTokens, [('fcm', 'tok-2')]);
        await t.beginPairing('arxa-pair:second'); // re-pair -> new session
        await pump();
        expect(mock.sessions, hasLength(2));
        expect(mock.sessions[1].registeredPushTokens, [('fcm', 'tok-2')]);
        expect(mock.sessions[0].closed, isTrue);
      },
    );

    test('resume delegates to the live session (foreground redial)', () async {
      await t.resume(); // no session: no-op
      await t.beginPairing('arxa-pair:abc');
      await pump();
      await t.resume();
      expect(mock.sessions.single.resumeCount, 1);
    });

    test(
      'unpair closes the session and lands on notPaired without error',
      () async {
        await t.beginPairing('arxa-pair:abc');
        await pump();
        mock.sessions.single.emit(
          StudioSessionStatus.connected,
          proxyPort: 8080,
        );
        await pump();
        await t.unpair();
        await pump();
        expect(mock.sessions.single.closed, isTrue);
        expect(t.current.state, ArxaConnectionState.notPaired);
        expect(t.current.error, isNull);
        expect(t.current.studioUrl, isNull);
      },
    );
  });

  group('FakeTransportService', () {
    test(
      'walks pairing -> connecting -> connected and serves the loopback URL',
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
      },
    );

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
