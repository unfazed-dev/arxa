import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:appbox_kit_core/appbox_kit_locator.dart';
import 'package:appbox_kit_core/services/error/appbox_kit_error_service.dart';
import 'package:appbox_kit_ui_library/services/notifications/appbox_kit_notification_service.dart';
import 'package:appbox_kit_ui_library/utils/kit_action/appbox_kit_action.dart';

/// Tests for `AppBoxKitAction.state$` — the observable per-widgetId busy/error
/// stream that replaces `withLoading(setBusy)` plumbing for stream-bound
/// views.
void main() {
  setUp(() async {
    appBoxKitLocator
      ..registerLazySingleton(() => Talker())
      ..registerLazySingleton(() => AppBoxKitErrorService())
      ..registerLazySingleton(() => DialogService())
      ..registerLazySingleton(() => BottomSheetService())
      ..registerLazySingleton(() => AppBoxKitNotificationService())
      ..registerLazySingleton(() => SnackbarService());
    // AppBoxKitErrorService.handle() touches its Talker field — LateInitializationError
    // if initialize() never ran (same boot-order rule as app main()).
    await appBoxKitLocator<AppBoxKitErrorService>().initialize();
  });

  tearDown(() => appBoxKitLocator.reset());

  group('AppBoxKitAction.state\$', () {
    test(
        'kit.ui-library.action-state — starts idle (busy false, no error) for an unknown widgetId',
        () {
      final state = AppBoxKitAction.state$(widgetId: 'state.unknown');
      expect(state.value.busy, isFalse);
      expect(state.value.errorMessage, isNull);
      AppBoxKitAction.dispose(widgetId: 'state.unknown');
    });

    test(
        'kit.ui-library.action-state — busy true while running, false after success, no error',
        () async {
      final gate = Completer<void>();
      final states = <AppBoxKitActionState>[];
      final sub =
          AppBoxKitAction.state$(widgetId: 'state.success').listen(states.add);

      final future = AppBoxKitAction.run<String>(
        () async {
          await gate.future;
          return 'ok';
        },
        widgetId: 'state.success',
      ).execute();

      expect(
          AppBoxKitAction.state$(widgetId: 'state.success').value.busy, isTrue);
      gate.complete();
      expect(await future, 'ok');
      await Future<void>.delayed(Duration.zero);

      expect(AppBoxKitAction.state$(widgetId: 'state.success').value.busy,
          isFalse);
      expect(
          AppBoxKitAction.state$(widgetId: 'state.success').value.errorMessage,
          isNull);
      expect(states.map((s) => s.busy), containsAllInOrder([true, false]));

      await sub.cancel();
      AppBoxKitAction.dispose(widgetId: 'state.success');
    });

    test(
        'kit.ui-library.action-state — error message persists after failure until the next run starts',
        () async {
      // Bind first, like a view does — subjects are created on read, so an
      // unobserved widgetId records nothing.
      final state = AppBoxKitAction.state$(widgetId: 'state.error');
      await expectLater(
        AppBoxKitAction.run<String>(
          () async => throw Exception('boom'),
          widgetId: 'state.error',
        ).completeOnError('Could not save', withValue: '').execute(),
        completion(''),
      );

      final afterFailure = state.value;
      expect(afterFailure.busy, isFalse);
      expect(afterFailure.errorMessage, 'Could not save');

      // Next run starts: stale error clears, busy set.
      final rerun = AppBoxKitAction.run<String>(
        () async => 'fixed',
        widgetId: 'state.error',
      ).execute();
      final running = AppBoxKitAction.state$(widgetId: 'state.error').value;
      expect(running.busy, isTrue);
      expect(running.errorMessage, isNull);
      expect(await rerun, 'fixed');

      AppBoxKitAction.dispose(widgetId: 'state.error');
    });

    test(
        'kit.ui-library.action-state — falls back to the exception toString without a configured message',
        () async {
      final state = AppBoxKitAction.state$(widgetId: 'state.raw');
      await expectLater(
        AppBoxKitAction.run<String>(
          () async => throw Exception('raw failure'),
          widgetId: 'state.raw',
        ).execute(),
        throwsException,
      );
      expect(state.value.busy, isFalse);
      expect(state.value.errorMessage, 'Exception: raw failure');
      AppBoxKitAction.dispose(widgetId: 'state.raw');
    });

    test('kit.ui-library.action-state — dispose closes the state subject',
        () async {
      final state = AppBoxKitAction.state$(widgetId: 'state.dispose');
      expect(state.value.busy, isFalse);
      AppBoxKitAction.dispose(widgetId: 'state.dispose');
      // A fresh state$ after dispose is a new idle subject.
      expect(AppBoxKitAction.state$(widgetId: 'state.dispose').value.busy,
          isFalse);
      AppBoxKitAction.dispose(widgetId: 'state.dispose');
    });
  });
}
