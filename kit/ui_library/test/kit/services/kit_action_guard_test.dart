import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:appbox_kit_core/kit_locator.dart';
import 'package:appbox_kit_core/services/error/kit_error_service.dart';
import 'package:ui_library/services/notifications/kit_notification_service.dart';
import 'package:ui_library/utils/kit_action/kit_action.dart';
import 'package:ui_library/utils/kit_action/kit_action_types.dart';

/// Tests for the two KitAction hardening changes:
///
/// 1. Re-entry guard (default on): a second execute() while the same
///    widgetId is in flight is dropped — fallback when set, else
///    GuardedException. `.withParallelExecution()` opts out.
/// 2. `KitAction.watch` accepts any `Stream` (not only BehaviorSubjects) so
///    callers compose with rxdart (switchMap etc.) and watch one stream.
void main() {
  setUp(() {
    locator
      ..registerLazySingleton(() => Talker())
      ..registerLazySingleton(() => KitErrorService())
      ..registerLazySingleton(() => DialogService())
      ..registerLazySingleton(() => BottomSheetService())
      ..registerLazySingleton(() => KitNotificationService())
      ..registerLazySingleton(() => SnackbarService());
  });

  tearDown(() => locator.reset());

  group('re-entry guard', () {
    test('drops an overlapping call with the same widgetId', () async {
      final gate = Completer<void>();
      var runs = 0;

      final first = KitAction.run<String>(
        operation: () async {
          runs++;
          await gate.future;
          return 'first';
        },
        widgetId: 'guard.drop',
      ).execute();

      await expectLater(
        KitAction.run<String>(
          operation: () async {
            runs++;
            return 'second';
          },
          widgetId: 'guard.drop',
        ).execute(),
        throwsA(isA<GuardedException>()),
      );

      gate.complete();
      expect(await first, 'first');
      expect(runs, 1);
    });

    test('dropped call completes with the fallback when one is set', () async {
      final gate = Completer<void>();

      final first = KitAction.run<String>(
        operation: () async {
          await gate.future;
          return 'first';
        },
        widgetId: 'guard.fallback',
      ).execute();

      final second = await KitAction.run<String>(
        operation: () async => 'second',
        widgetId: 'guard.fallback',
      ).withErrorFallback('failed', fallback: 'fallback').execute();

      expect(second, 'fallback');
      gate.complete();
      expect(await first, 'first');
    });

    test('sequential runs of the same widgetId both execute', () async {
      var runs = 0;
      Future<String> once() => KitAction.run<String>(
            operation: () async => 'run ${++runs}',
            widgetId: 'guard.sequential',
          ).execute();

      expect(await once(), 'run 1');
      expect(await once(), 'run 2');
      expect(runs, 2);
    });

    test('withParallelExecution opts out of the guard', () async {
      final gate = Completer<void>();
      var runs = 0;

      Future<String> call() => KitAction.run<String>(
            operation: () async {
              runs++;
              await gate.future;
              return 'ok';
            },
            widgetId: 'guard.parallel',
          ).withParallelExecution().execute();

      final first = call();
      final second = call();
      gate.complete();
      expect(await first, 'ok');
      expect(await second, 'ok');
      expect(runs, 2);
    });

    test('different widgetIds run concurrently by default', () async {
      final gate = Completer<void>();
      var runs = 0;

      Future<String> call(String id) => KitAction.run<String>(
            operation: () async {
              runs++;
              await gate.future;
              return id;
            },
            widgetId: id,
          ).execute();

      final a = call('guard.a');
      final b = call('guard.b');
      gate.complete();
      expect(await a, 'guard.a');
      expect(await b, 'guard.b');
      expect(runs, 2);
    });
  });

  group('watch (any Stream)', () {
    test('fires the callback for plain single-subscription streams', () async {
      final controller = StreamController<int>();
      var fires = 0;
      final seen = <dynamic>[];

      KitAction.watch(
        widgetId: 'watch.plain',
        streams: [controller.stream],
        callback: (value) {
          fires++;
          seen.add(value);
        },
      );

      controller.add(1);
      controller.add(2);
      await pumpEventQueue();
      expect(fires, 2);
      expect(seen, [1, 2], reason: 'the callback receives the emitted value');

      KitAction.dispose(widgetId: 'watch.plain');
      controller.add(3);
      await pumpEventQueue();
      expect(fires, 2, reason: 'dispose cancels the subscription');

      await controller.close();
    });

    test('callback exceptions route to onError, not the zone', () async {
      final controller = StreamController<int>();
      Exception? caught;

      KitAction.watch(
        widgetId: 'watch.error',
        streams: [controller.stream],
        callback: (_) => throw Exception('boom'),
        onError: (e, s) => caught = e,
      );

      controller.add(1);
      await pumpEventQueue();
      expect(caught?.toString(), contains('boom'));

      KitAction.dispose(widgetId: 'watch.error');
      await controller.close();
    });
  });
}
