import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_core/services/error/arxa_kit_error_service.dart';
import 'package:arxa_kit_ui_library/services/notifications/arxa_kit_notification_service.dart';
import 'package:arxa_kit_ui_library/utils/kit_action/arxa_kit_action.dart';

/// Tests for `ArxaKitAction.state$` — the observable per-widgetId busy/error
/// stream that replaces `withLoading(setBusy)` plumbing for stream-bound
/// views.
void main() {
  setUp(() async {
    arxaKitLocator
      ..registerLazySingleton(() => Talker())
      ..registerLazySingleton(() => ArxaKitErrorService())
      ..registerLazySingleton(() => DialogService())
      ..registerLazySingleton(() => BottomSheetService())
      ..registerLazySingleton(() => ArxaKitNotificationService())
      ..registerLazySingleton(() => SnackbarService());
    // ArxaKitErrorService.handle() touches its Talker field — LateInitializationError
    // if initialize() never ran (same boot-order rule as app main()).
    await arxaKitLocator<ArxaKitErrorService>().initialize();
  });

  tearDown(() => arxaKitLocator.reset());

  group('ArxaKitAction.state\$', () {
    test(
        'kit.ui-library.action-state — starts idle (busy false, no error) for an unknown widgetId',
        () {
      final state = ArxaKitAction.state$(widgetId: 'state.unknown');
      expect(state.value.busy, isFalse);
      expect(state.value.errorMessage, isNull);
      ArxaKitAction.dispose(widgetId: 'state.unknown');
    });

    test(
        'kit.ui-library.action-state — busy true while running, false after success, no error',
        () async {
      final gate = Completer<void>();
      final states = <ArxaKitActionState>[];
      final sub =
          ArxaKitAction.state$(widgetId: 'state.success').listen(states.add);

      final future = ArxaKitAction.run<String>(
        () async {
          await gate.future;
          return 'ok';
        },
        widgetId: 'state.success',
      ).execute();

      expect(
          ArxaKitAction.state$(widgetId: 'state.success').value.busy, isTrue);
      gate.complete();
      expect(await future, 'ok');
      await Future<void>.delayed(Duration.zero);

      expect(ArxaKitAction.state$(widgetId: 'state.success').value.busy,
          isFalse);
      expect(
          ArxaKitAction.state$(widgetId: 'state.success').value.errorMessage,
          isNull);
      expect(states.map((s) => s.busy), containsAllInOrder([true, false]));

      await sub.cancel();
      ArxaKitAction.dispose(widgetId: 'state.success');
    });

    test(
        'kit.ui-library.action-state — error message persists after failure until the next run starts',
        () async {
      // Bind first, like a view does — subjects are created on read, so an
      // unobserved widgetId records nothing.
      final state = ArxaKitAction.state$(widgetId: 'state.error');
      await expectLater(
        ArxaKitAction.run<String>(
          () async => throw Exception('boom'),
          widgetId: 'state.error',
        ).completeOnError('Could not save', withValue: '').execute(),
        completion(''),
      );

      final afterFailure = state.value;
      expect(afterFailure.busy, isFalse);
      expect(afterFailure.errorMessage, 'Could not save');

      // Next run starts: stale error clears, busy set.
      final rerun = ArxaKitAction.run<String>(
        () async => 'fixed',
        widgetId: 'state.error',
      ).execute();
      final running = ArxaKitAction.state$(widgetId: 'state.error').value;
      expect(running.busy, isTrue);
      expect(running.errorMessage, isNull);
      expect(await rerun, 'fixed');

      ArxaKitAction.dispose(widgetId: 'state.error');
    });

    test(
        'kit.ui-library.action-state — falls back to the exception toString without a configured message',
        () async {
      final state = ArxaKitAction.state$(widgetId: 'state.raw');
      await expectLater(
        ArxaKitAction.run<String>(
          () async => throw Exception('raw failure'),
          widgetId: 'state.raw',
        ).execute(),
        throwsException,
      );
      expect(state.value.busy, isFalse);
      expect(state.value.errorMessage, 'Exception: raw failure');
      ArxaKitAction.dispose(widgetId: 'state.raw');
    });

    test('kit.ui-library.action-state — dispose closes the state subject',
        () async {
      final state = ArxaKitAction.state$(widgetId: 'state.dispose');
      expect(state.value.busy, isFalse);
      ArxaKitAction.dispose(widgetId: 'state.dispose');
      // A fresh state$ after dispose is a new idle subject.
      expect(ArxaKitAction.state$(widgetId: 'state.dispose').value.busy,
          isFalse);
      ArxaKitAction.dispose(widgetId: 'state.dispose');
    });
  });
}
