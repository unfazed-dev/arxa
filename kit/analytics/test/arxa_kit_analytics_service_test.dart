import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_analytics/arxa_kit_analytics.dart';
import 'package:arxa_kit_analytics/arxa_kit_testing.dart';

void main() {
  group('ArxaKitAnalyticsService', () {
    test('kit.analytics.fan-out — forwards a track event to every registered backend',
        () async {
      // given
      final first = RecordingArxaKitAnalyticsBackend(id: 'first');
      final second = RecordingArxaKitAnalyticsBackend(id: 'second');
      final service = ArxaKitAnalyticsService(backends: [first, second]);
      // when
      await service.logEvent('checkout_completed', params: {'total': 42});
      // then
      expect(first.eventsNamed('checkout_completed'), hasLength(1));
      expect(second.eventsNamed('checkout_completed'), hasLength(1));
      expect(first.lastEvent!.params['total'], 42);
      expect(second.lastEvent!.params['total'], 42);
    });

    test('kit.analytics.fan-out — every backend shares the timestamp from the injected clock',
        () async {
      // given
      final first = RecordingArxaKitAnalyticsBackend(id: 'first');
      final second = RecordingArxaKitAnalyticsBackend(id: 'second');
      final fixed = DateTime.utc(2026, 8, 6, 12, 0, 0);
      final service = ArxaKitAnalyticsService(
        backends: [first, second],
        clock: () => fixed,
      );
      // when
      await service.logEvent('app_opened');
      // then
      expect(first.lastEvent!.timestamp, fixed);
      expect(second.lastEvent!.timestamp, fixed);
    });

    test('kit.analytics.fan-out — an event without params arrives with empty params',
        () async {
      // given
      final recorder = RecordingArxaKitAnalyticsBackend();
      final service = ArxaKitAnalyticsService(backends: [recorder]);
      // when
      await service.logEvent('app_opened');
      // then
      expect(recorder.lastEvent!.params, isEmpty);
    });

    test('kit.analytics.fan-out — forwards a screen view with name, class and timestamp',
        () async {
      // given
      final recorder = RecordingArxaKitAnalyticsBackend();
      final fixed = DateTime.utc(2026, 8, 6, 9, 30, 0);
      final service = ArxaKitAnalyticsService(
        backends: [recorder],
        clock: () => fixed,
      );
      // when
      await service.screenView('FolderList', screenClass: 'FolderListView');
      // then
      expect(recorder.screenViews, hasLength(1));
      expect(recorder.lastScreenView!.screenName, 'FolderList');
      expect(recorder.lastScreenView!.screenClass, 'FolderListView');
      expect(recorder.lastScreenView!.timestamp, fixed);
    });

    test('kit.analytics.fan-out — forwards a timing with duration and params',
        () async {
      // given
      final recorder = RecordingArxaKitAnalyticsBackend();
      final service = ArxaKitAnalyticsService(backends: [recorder]);
      // when
      await service.timing('time_to_interactive',
          const Duration(milliseconds: 1200), params: {'route': '/home'});
      // then
      expect(recorder.timings, hasLength(1));
      expect(recorder.timings.single.name, 'time_to_interactive');
      expect(recorder.timings.single.duration,
          const Duration(milliseconds: 1200));
      expect(recorder.timings.single.params['route'], '/home');
    });

    test('kit.analytics.fan-out — setting then clearing a user property records the clear as a null value',
        () async {
      // given
      final recorder = RecordingArxaKitAnalyticsBackend();
      final service = ArxaKitAnalyticsService(backends: [recorder]);
      // when
      await service.setUserProperty('plan', 'pro');
      await service.setUserProperty('plan', null);
      // then
      expect(recorder.userProperties, hasLength(2));
      expect(recorder.userProperty('plan'), isNull);
    });

    test('kit.analytics.fan-out — flush reaches every registered backend', () async {
      // given
      final first = RecordingArxaKitAnalyticsBackend(id: 'first');
      final second = RecordingArxaKitAnalyticsBackend(id: 'second');
      final service = ArxaKitAnalyticsService(backends: [first, second]);
      // when
      await service.flush();
      // then
      expect(first.flushCount, 1);
      expect(second.flushCount, 1);
    });

    test('kit.analytics.fan-out — calls with no registered backends complete without error',
        () async {
      // given
      final service = ArxaKitAnalyticsService();
      // when / then
      await service.logEvent('app_opened');
      await service.screenView('Home');
      await service.timing('tti', const Duration(milliseconds: 10));
      await service.setUserProperty('plan', 'pro');
      await service.flush();
    });

    test('kit.analytics.error-isolation — a throwing backend does not break the other backends',
        () async {
      // given — the thrower is registered first, so both healthy backends sit
      // behind it in fan-out order.
      final recorder = RecordingArxaKitAnalyticsBackend(id: 'healthy');
      final service = ArxaKitAnalyticsService(
        backends: [ThrowingArxaKitAnalyticsBackend(), recorder],
        onError: (_, __, ___) {},
      );
      // when
      await service.logEvent('checkout_completed');
      await service.screenView('Home');
      await service.flush();
      // then
      expect(recorder.didLog('checkout_completed'), isTrue);
      expect(recorder.screenViews, hasLength(1));
      expect(recorder.flushCount, 1);
    });

    test('kit.analytics.error-isolation — a backend error is routed to onError with the backend id and never rethrown',
        () async {
      // given
      final reported = <String>[];
      final service = ArxaKitAnalyticsService(
        backends: [ThrowingArxaKitAnalyticsBackend(id: 'flaky')],
        onError: (id, error, stackTrace) => reported.add(id),
      );
      // when — completes normally despite the backend throwing on every call.
      await service.logEvent('app_opened');
      await service.flush();
      // then
      expect(reported, ['flaky', 'flaky']);
    });

    test('kit.analytics.registration — re-registering an id replaces the previous backend',
        () async {
      // given
      final stale = RecordingArxaKitAnalyticsBackend(id: 'console');
      final live = RecordingArxaKitAnalyticsBackend(id: 'console');
      final service = ArxaKitAnalyticsService(backends: [stale]);
      // when
      service.registerBackend(live);
      await service.logEvent('app_opened');
      // then
      expect(stale.events, isEmpty);
      expect(live.didLog('app_opened'), isTrue);
    });

    test('kit.analytics.registration — a removed backend no longer receives calls',
        () async {
      // given
      final removed = RecordingArxaKitAnalyticsBackend(id: 'removed');
      final kept = RecordingArxaKitAnalyticsBackend(id: 'kept');
      final service = ArxaKitAnalyticsService(backends: [removed, kept]);
      // when
      final wasRemoved = service.removeBackend('removed');
      await service.logEvent('app_opened');
      // then
      expect(wasRemoved, isTrue);
      expect(removed.events, isEmpty);
      expect(kept.didLog('app_opened'), isTrue);
    });

    test('kit.analytics.registration — removing an unknown id reports false and leaves fan-out untouched',
        () async {
      // given
      final recorder = RecordingArxaKitAnalyticsBackend(id: 'kept');
      final service = ArxaKitAnalyticsService(backends: [recorder]);
      // when
      final wasRemoved = service.removeBackend('missing');
      await service.logEvent('app_opened');
      // then
      expect(wasRemoved, isFalse);
      expect(recorder.didLog('app_opened'), isTrue);
    });

    test('kit.analytics.registration — clearBackends stops all fan-out', () async {
      // given
      final recorder = RecordingArxaKitAnalyticsBackend();
      final service = ArxaKitAnalyticsService(backends: [recorder]);
      // when
      service.clearBackends();
      await service.logEvent('app_opened');
      // then
      expect(recorder.events, isEmpty);
    });
  });

  group('ArxaKitDebugConsoleAnalyticsBackend', () {
    test('kit.analytics.debug-console — tolerates every call with no SDK attached',
        () async {
      // given — the port contract: a backend must tolerate being called before
      // any underlying SDK is ready; the console default has none at all.
      final backend = ArxaKitDebugConsoleAnalyticsBackend();
      // when / then — every call completes without throwing.
      await backend.logEvent(ArxaKitAnalyticsEvent(
          name: 'app_opened', timestamp: DateTime.utc(2026, 8, 6)));
      await backend.screenView(ArxaKitScreenView(
          screenName: 'Home', timestamp: DateTime.utc(2026, 8, 6)));
      await backend.timing(ArxaKitAnalyticsTiming(
          name: 'tti',
          duration: const Duration(milliseconds: 10),
          timestamp: DateTime.utc(2026, 8, 6)));
      await backend.setUserProperty(const ArxaKitUserProperty('plan', 'pro'));
      await backend.flush();
    });
  });
}
