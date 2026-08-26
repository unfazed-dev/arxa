import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:arxa_kit_notifications/arxa_kit_notifications.dart';
import 'package:arxa_kit_notifications/arxa_kit_testing.dart';

/// Behavior tests for arxa_kit_notifications, per the arxa behavior-TDD
/// canon (skills/arxa-tester/behavior-tdd-rules.md).
///
/// The real [LocalArxaKitNotificationsService] is exercised against the
/// flutter_local_notifications MethodChannel
/// (`dexterous.com/flutter/local_notifications`), intercepted with a
/// TestDefaultBinaryMessenger mock handler — the same pattern as
/// kit/ui_library's cupertino_native method-channel tests. The platform
/// instance is swapped per group (Android/iOS) and restored in tearDown; this
/// kit is standalone and has no arxaKitLocator, so the channel handler,
/// platform instance, and target-platform override are the static state reset
/// per test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('LocalArxaKitNotificationsService (Android)', () {
    late List<MethodCall> calls;
    bool? permissionAnswer;

    setUp(() {
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      calls = [];
      permissionAnswer = null;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'initialize':
            return true;
          case 'requestNotificationsPermission':
            return permissionAnswer;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'kit.notifications.permission — a granted OS prompt resolves to authorized',
      () async {
        // given
        final service = LocalArxaKitNotificationsService();
        permissionAnswer = true;
        // when
        final result = await service.requestPermission();
        // then
        expect(result.status, ArxaKitNotificationAuthorization.authorized);
        expect(result.isGranted, isTrue);
        expect(
          calls.map((c) => c.method),
          contains('requestNotificationsPermission'),
        );
      },
    );

    test(
      'kit.notifications.permission — a declined OS prompt resolves to denied instead of throwing',
      () async {
        // given
        final service = LocalArxaKitNotificationsService();
        permissionAnswer = false;
        // when
        final result = await service.requestPermission();
        // then
        expect(result.status, ArxaKitNotificationAuthorization.denied);
        expect(result.isGranted, isFalse);
      },
    );

    test(
      'kit.notifications.permission — no OS answer resolves to notDetermined',
      () async {
        // given
        final service = LocalArxaKitNotificationsService();
        permissionAnswer = null;
        // when
        final result = await service.requestPermission();
        // then
        expect(
          result.status,
          ArxaKitNotificationAuthorization.notDetermined,
        );
      },
    );

    test(
      'kit.notifications.permission — permissionStatus reports notDetermined without prompting the OS',
      () async {
        // given
        final service = LocalArxaKitNotificationsService();
        // when
        final result = await service.permissionStatus();
        // then
        expect(
          result.status,
          ArxaKitNotificationAuthorization.notDetermined,
        );
        expect(
          calls.map((c) => c.method),
          isNot(contains('requestNotificationsPermission')),
        );
      },
    );

    test(
      'kit.notifications.permission — initialize registers the default Android icon and defers the OS prompt',
      () async {
        // given
        final service = LocalArxaKitNotificationsService();
        // when
        await service.initialize();
        // then — the plugin was initialized with the service's default icon…
        final init = calls.singleWhere((c) => c.method == 'initialize');
        expect(
          (init.arguments as Map)['defaultIcon'],
          '@mipmap/ic_launcher',
        );
        // …and no permission prompt went out at boot.
        expect(
          calls.map((c) => c.method),
          isNot(contains('requestNotificationsPermission')),
        );
      },
    );

    test(
      'kit.notifications.local — showLocalNotification lazily initializes once, then delivers each notification',
      () async {
        // given
        final service = LocalArxaKitNotificationsService();
        // when
        await service.showLocalNotification(const ArxaKitLocalNotification(
          id: 1,
          title: 'Hello',
          body: 'First',
          payload: 'p1',
        ));
        await service.showLocalNotification(const ArxaKitLocalNotification(
          id: 2,
          title: 'Again',
        ));
        // then — one lazy initialize, then both shows in order.
        expect(
          calls.map((c) => c.method).toList(),
          ['initialize', 'show', 'show'],
        );
        final first = calls[1].arguments as Map;
        expect(first['id'], 1);
        expect(first['title'], 'Hello');
        expect(first['body'], 'First');
        expect(first['payload'], 'p1');
      },
    );

    test(
      'kit.notifications.local — a notification without a channel falls back to the default Android channel, an explicit one wins',
      () async {
        // given
        final service = LocalArxaKitNotificationsService(
          defaultChannelId: 'kit_default',
          defaultChannelName: 'Kit Default',
        );
        // when
        await service.showLocalNotification(
          const ArxaKitLocalNotification(id: 1, title: 'fallback'),
        );
        await service.showLocalNotification(const ArxaKitLocalNotification(
          id: 2,
          title: 'explicit',
          androidChannelId: 'urgent',
          androidChannelName: 'Urgent',
        ));
        // then
        final shows = calls.where((c) => c.method == 'show').toList();
        final fallback =
            (shows[0].arguments as Map)['platformSpecifics'] as Map;
        expect(fallback['channelId'], 'kit_default');
        expect(fallback['channelName'], 'Kit Default');
        final explicit =
            (shows[1].arguments as Map)['platformSpecifics'] as Map;
        expect(explicit['channelId'], 'urgent');
      },
    );

    test(
      'kit.notifications.local — cancel forwards the id and cancelAll clears every notification',
      () async {
        // given
        final service = LocalArxaKitNotificationsService();
        // when
        await service.cancel(7);
        await service.cancelAll();
        // then
        expect(calls[0].method, 'cancel');
        expect((calls[0].arguments as Map)['id'], 7);
        expect(calls[1].method, 'cancelAll');
      },
    );

    test(
      'kit.notifications.badge — setBadgeCount throws UnsupportedError because flutter_local_notifications has no standalone badge setter',
      () async {
        // given
        final service = LocalArxaKitNotificationsService();
        // when / then
        await expectLater(
          service.setBadgeCount(3),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'kit.notifications.badge — clearBadge delegates to the unsupported standalone setter and also throws',
      () async {
        // given
        final service = LocalArxaKitNotificationsService();
        // when / then
        await expectLater(service.clearBadge(), throwsUnsupportedError);
      },
    );

    test(
      'kit.notifications.token — the local default is not a push provider: no token, no token emissions',
      () async {
        // given
        final service = LocalArxaKitNotificationsService();
        var emissions = 0;
        final sub = service.tokenStream.listen((_) => emissions++);
        addTearDown(sub.cancel);
        // when
        final token = await service.currentToken();
        await pumpEventQueue();
        // then
        expect(token, isNull);
        expect(emissions, isZero);
      },
    );

    test(
      'kit.notifications.foreground — the local default emits no foreground remote messages',
      () async {
        // given
        final service = LocalArxaKitNotificationsService();
        var emissions = 0;
        final sub = service.foregroundMessages.listen((_) => emissions++);
        addTearDown(sub.cancel);
        // when
        await pumpEventQueue();
        // then
        expect(emissions, isZero);
      },
    );
  });

  group('LocalArxaKitNotificationsService (iOS)', () {
    late List<MethodCall> calls;
    bool? permissionAnswer;

    setUp(() {
      FlutterLocalNotificationsPlatform.instance =
          IOSFlutterLocalNotificationsPlugin();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      calls = [];
      permissionAnswer = null;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'initialize':
            return true;
          case 'requestPermissions':
            return permissionAnswer;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'kit.notifications.permission — the Darwin request forwards the alert/badge/sound flags and maps the answer',
      () async {
        // given
        final service = LocalArxaKitNotificationsService();
        permissionAnswer = true;
        // when
        final granted = await service.requestPermission();
        final partial = await service.requestPermission(
          const ArxaKitNotificationPermissionRequest(
            alert: false,
            badge: false,
            sound: false,
          ),
        );
        // then — both requests forwarded their flags…
        final requests =
            calls.where((c) => c.method == 'requestPermissions').toList();
        final defaults = requests[0].arguments as Map;
        expect(defaults['alert'], isTrue);
        expect(defaults['badge'], isTrue);
        expect(defaults['sound'], isTrue);
        final narrowed = requests[1].arguments as Map;
        expect(narrowed['alert'], isFalse);
        expect(narrowed['badge'], isFalse);
        expect(narrowed['sound'], isFalse);
        // …and the scripted grant resolved to authorized for both.
        expect(granted.status, ArxaKitNotificationAuthorization.authorized);
        expect(partial.status, ArxaKitNotificationAuthorization.authorized);
      },
    );

    test(
      'kit.notifications.permission — initialize never prompts on Darwin: alert/badge/sound requests are all deferred',
      () async {
        // given
        final service = LocalArxaKitNotificationsService();
        // when
        await service.initialize();
        // then
        final init = calls.singleWhere((c) => c.method == 'initialize');
        final args = init.arguments as Map;
        expect(args['requestAlertPermission'], isFalse);
        expect(args['requestBadgePermission'], isFalse);
        expect(args['requestSoundPermission'], isFalse);
      },
    );

    test(
      'kit.notifications.badge — a shown notification carries its badgeCount to Darwin as the app-icon badge',
      () async {
        // given
        final service = LocalArxaKitNotificationsService();
        // when
        await service.showLocalNotification(const ArxaKitLocalNotification(
          id: 9,
          title: 'Badge me',
          badgeCount: 4,
        ));
        // then
        final show = calls.singleWhere((c) => c.method == 'show');
        final specifics =
            (show.arguments as Map)['platformSpecifics'] as Map;
        expect(specifics['badgeNumber'], 4);
      },
    );
  });

  group('FakeArxaKitNotificationsService', () {
    test(
      'kit.notifications.permission — the scripted outcome is returned and the request is recorded',
      () async {
        // given
        final fake = FakeArxaKitNotificationsService()
          ..permissionResult = const ArxaKitNotificationPermissionResult(
              ArxaKitNotificationAuthorization.denied);
        const request =
            ArxaKitNotificationPermissionRequest(badge: false);
        // when
        final result = await fake.requestPermission(request);
        // then
        expect(result.status, ArxaKitNotificationAuthorization.denied);
        expect(fake.permissionRequests, [request]);
        final status = await fake.permissionStatus();
        expect(status.status, ArxaKitNotificationAuthorization.denied);
      },
    );

    test(
      'kit.notifications.token — emitted tokens stream in order and update currentToken',
      () async {
        // given
        final fake = FakeArxaKitNotificationsService();
        final t1 = ArxaKitPushToken(
          value: 'token-1',
          issuedAt: DateTime(2026),
          provider: ArxaKitPushProvider.fcm,
        );
        final t2 = ArxaKitPushToken(
          value: 'token-2',
          issuedAt: DateTime(2026, 2),
          provider: ArxaKitPushProvider.fcm,
        );
        final expectation = expectLater(
          fake.tokenStream,
          emitsInOrder([t1, t2]),
        );
        // when
        fake.emitToken(t1);
        fake.emitToken(t2);
        // then
        await expectation.timeout(const Duration(milliseconds: 500));
        expect(await fake.currentToken(), t2);
      },
    );

    test(
      'kit.notifications.foreground — emitted remote messages reach foregroundMessages in order',
      () async {
        // given
        final fake = FakeArxaKitNotificationsService();
        final m1 = ArxaKitRemoteMessage(
          receivedAt: DateTime(2026),
          messageId: 'm1',
          title: 'One',
        );
        final m2 = ArxaKitRemoteMessage(
          receivedAt: DateTime(2026, 2),
          messageId: 'm2',
          data: const {'route': '/inbox'},
        );
        final expectation = expectLater(
          fake.foregroundMessages,
          emitsInOrder([m1, m2]),
        );
        // when
        fake.emitMessage(m1);
        fake.emitMessage(m2);
        // then
        await expectation.timeout(const Duration(milliseconds: 500));
      },
    );

    test(
      'kit.notifications.local — shown notifications and cancels are recorded in call order',
      () async {
        // given
        final fake = FakeArxaKitNotificationsService();
        // when
        await fake.showLocalNotification(
          const ArxaKitLocalNotification(id: 1, title: 'A'),
        );
        await fake.showLocalNotification(
          const ArxaKitLocalNotification(id: 2, title: 'B'),
        );
        await fake.cancel(1);
        await fake.cancelAll();
        // then
        expect(fake.shown.map((n) => n.title), ['A', 'B']);
        expect(fake.cancelled, [1]);
        expect(fake.cancelAllCount, 1);
      },
    );

    test(
      'kit.notifications.badge — setBadgeCount records the count and clearBadge records a zero',
      () async {
        // given
        final fake = FakeArxaKitNotificationsService();
        // when
        await fake.setBadgeCount(5);
        await fake.clearBadge();
        // then
        expect(fake.badgeCounts, [5, 0]);
      },
    );
  });

  group('FakeArxaKitOutboundMessageSink', () {
    const message = ArxaKitOutboundMessage(
      to: '+15551234567',
      body: 'Your code is 1234',
    );

    test(
      'kit.notifications.outbound — send records the message on the sink channel',
      () async {
        // given
        final sink = FakeArxaKitOutboundMessageSink(channel: 'sms');
        // when
        await sink.send(message);
        // then
        expect(sink.channel, 'sms');
        expect(sink.sent, [message]);
      },
    );

    test(
      'kit.notifications.outbound — a scripted failure throws from send so callers can react, and nothing is recorded',
      () async {
        // given
        final sink = FakeArxaKitOutboundMessageSink()
          ..failWith = StateError('provider down');
        // when / then
        await expectLater(sink.send(message), throwsStateError);
        expect(sink.sent, isEmpty);
      },
    );
  });

  group('stub backends', () {
    const message = ArxaKitOutboundMessage(
      to: 'a@b.c',
      subject: 'Hi',
      body: 'Body',
    );

    test(
      'kit.notifications.push — the FCM push backend is a stub: every surface throws UnimplementedError',
      () async {
        // given
        final backend = ArxaKitFcmPushBackend();
        // when / then
        await expectLater(backend.initialize(), throwsUnimplementedError);
        await expectLater(
          backend.requestPermission(),
          throwsUnimplementedError,
        );
        await expectLater(
          backend.currentToken(),
          throwsUnimplementedError,
        );
      },
    );

    test(
      'kit.notifications.outbound — the SMS backend is an sms-channel stub that throws UnimplementedError on send',
      () async {
        // given
        final backend = ArxaKitSmsBackend();
        // when / then
        expect(backend.channel, 'sms');
        await expectLater(backend.send(message), throwsUnimplementedError);
      },
    );

    test(
      'kit.notifications.outbound — the email backend is an email-channel stub that throws UnimplementedError on send',
      () async {
        // given
        final backend = ArxaKitEmailBackend();
        // when / then
        expect(backend.channel, 'email');
        await expectLater(backend.send(message), throwsUnimplementedError);
      },
    );
  });
}
