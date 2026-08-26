import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_core/services/error/arxa_kit_error_service.dart';
import 'package:arxa_kit_ui_library/services/notifications/arxa_kit_notification_service.dart';
import 'package:arxa_kit_ui_library/utils/kit_action/arxa_kit_action.dart';
import 'package:arxa_kit_ui_library/utils/kit_action/arxa_kit_action_types.dart';

/// Tests for the two ArxaKitAction hardening changes:
///
/// 1. Re-entry guard (default on): a second execute() while the same
///    widgetId is in flight is dropped — fallback when set, else
///    ArxaKitGuardedException. `.withParallelExecution()` opts out.
/// 2. `ArxaKitAction.listen` accepts any `Stream` (not only BehaviorSubjects) so
///    callers compose with rxdart (switchMap etc.) and listen one stream.
void main() {
  setUp(() {
    arxaKitLocator
      ..registerLazySingleton(() => Talker())
      ..registerLazySingleton(() => ArxaKitErrorService())
      ..registerLazySingleton(() => DialogService())
      ..registerLazySingleton(() => BottomSheetService())
      ..registerLazySingleton(() => ArxaKitNotificationService())
      ..registerLazySingleton(() => SnackbarService());
  });

  tearDown(() => arxaKitLocator.reset());

  group('re-entry guard', () {
    test(
        'kit.ui-library.action-guard — drops an overlapping call with the same widgetId',
        () async {
      final gate = Completer<void>();
      var runs = 0;

      final first = ArxaKitAction.run<String>(
        () async {
          runs++;
          await gate.future;
          return 'first';
        },
        widgetId: 'guard.drop',
      ).execute();

      await expectLater(
        ArxaKitAction.run<String>(
          () async {
            runs++;
            return 'second';
          },
          widgetId: 'guard.drop',
        ).execute(),
        throwsA(isA<ArxaKitGuardedException>()),
      );

      gate.complete();
      expect(await first, 'first');
      expect(runs, 1);
    });

    test(
        'kit.ui-library.action-guard — dropped call completes with the fallback when one is set',
        () async {
      final gate = Completer<void>();

      final first = ArxaKitAction.run<String>(
        () async {
          await gate.future;
          return 'first';
        },
        widgetId: 'guard.fallback',
      ).execute();

      final second = await ArxaKitAction.run<String>(
        () async => 'second',
        widgetId: 'guard.fallback',
      ).completeOnError('failed', withValue: 'fallback').execute();

      expect(second, 'fallback');
      gate.complete();
      expect(await first, 'first');
    });

    test(
        'kit.ui-library.action-guard — sequential runs of the same widgetId both execute',
        () async {
      var runs = 0;
      Future<String> once() => ArxaKitAction.run<String>(
            () async => 'run ${++runs}',
            widgetId: 'guard.sequential',
          ).execute();

      expect(await once(), 'run 1');
      expect(await once(), 'run 2');
      expect(runs, 2);
    });

    test(
        'kit.ui-library.action-guard — withParallelExecution opts out of the guard',
        () async {
      final gate = Completer<void>();
      var runs = 0;

      Future<String> call() => ArxaKitAction.run<String>(
            () async {
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

    test(
        'kit.ui-library.action-guard — different widgetIds run concurrently by default',
        () async {
      final gate = Completer<void>();
      var runs = 0;

      Future<String> call(String id) => ArxaKitAction.run<String>(
            () async {
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

  group('listen (any Stream)', () {
    test(
        'kit.ui-library.action-guard — fires the callback for plain single-subscription streams',
        () async {
      final controller = StreamController<int>();
      var fires = 0;
      final seen = <dynamic>[];

      ArxaKitAction.listen(
        widgetId: 'listen.plain',
        to: [controller.stream],
        onData: (value) {
          fires++;
          seen.add(value);
        },
      );

      controller.add(1);
      controller.add(2);
      await pumpEventQueue();
      expect(fires, 2);
      expect(seen, [1, 2], reason: 'the callback receives the emitted value');

      ArxaKitAction.dispose(widgetId: 'listen.plain');
      controller.add(3);
      await pumpEventQueue();
      expect(fires, 2, reason: 'dispose cancels the subscription');

      await controller.close();
    });

    test(
        'kit.ui-library.action-guard — callback exceptions route to onError, not the zone',
        () async {
      final controller = StreamController<int>();
      Object? caught;

      ArxaKitAction.listen(
        widgetId: 'listen.error',
        to: [controller.stream],
        onData: (_) => throw Exception('boom'),
        onError: (error) => caught = error,
      );

      controller.add(1);
      await pumpEventQueue();
      expect(caught?.toString(), contains('boom'));

      ArxaKitAction.dispose(widgetId: 'listen.error');
      await controller.close();
    });
  });
}
