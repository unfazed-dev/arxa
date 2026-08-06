import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:appbox_kit_core/kit_locator.dart';
import 'package:appbox_kit_core/services/error/kit_error_service.dart';
import 'package:ui_library/services/notifications/kit_notification_service.dart';
import 'package:ui_library/utils/kit_action/kit_action.dart';

/// Tests for `KitAction.state$` — the observable per-widgetId busy/error
/// stream that replaces `withLoading(setBusy)` plumbing for stream-bound
/// views.
void main() {
  setUp(() async {
    locator
      ..registerLazySingleton(() => Talker())
      ..registerLazySingleton(() => KitErrorService())
      ..registerLazySingleton(() => DialogService())
      ..registerLazySingleton(() => BottomSheetService())
      ..registerLazySingleton(() => KitNotificationService())
      ..registerLazySingleton(() => SnackbarService());
    // KitErrorService.handle() touches its Talker field — LateInitializationError
    // if initialize() never ran (same boot-order rule as app main()).
    await locator<KitErrorService>().initialize();
  });

  tearDown(() => locator.reset());

  group('KitAction.state\$', () {
    test('starts idle (busy false, no error) for an unknown widgetId', () {
      final state = KitAction.state$(widgetId: 'state.unknown');
      expect(state.value.busy, isFalse);
      expect(state.value.errorMessage, isNull);
      KitAction.dispose(widgetId: 'state.unknown');
    });

    test('busy true while running, false after success, no error', () async {
      final gate = Completer<void>();
      final states = <KitActionState>[];
      final sub = KitAction.state$(widgetId: 'state.success').listen(states.add);

      final future = KitAction.run<String>(
        () async {
          await gate.future;
          return 'ok';
        },
        widgetId: 'state.success',
      ).execute();

      expect(KitAction.state$(widgetId: 'state.success').value.busy, isTrue);
      gate.complete();
      expect(await future, 'ok');
      await Future<void>.delayed(Duration.zero);

      expect(KitAction.state$(widgetId: 'state.success').value.busy, isFalse);
      expect(KitAction.state$(widgetId: 'state.success').value.errorMessage, isNull);
      expect(states.map((s) => s.busy), containsAllInOrder([true, false]));

      await sub.cancel();
      KitAction.dispose(widgetId: 'state.success');
    });

    test('error message persists after failure until the next run starts',
        () async {
      // Bind first, like a view does — subjects are created on read, so an
      // unobserved widgetId records nothing.
      final state = KitAction.state$(widgetId: 'state.error');
      await expectLater(
        KitAction.run<String>(
          () async => throw Exception('boom'),
          widgetId: 'state.error',
        ).completeOnError('Could not save', withValue: '').execute(),
        completion(''),
      );

      final afterFailure = state.value;
      expect(afterFailure.busy, isFalse);
      expect(afterFailure.errorMessage, 'Could not save');

      // Next run starts: stale error clears, busy set.
      final rerun = KitAction.run<String>(
        () async => 'fixed',
        widgetId: 'state.error',
      ).execute();
      final running = KitAction.state$(widgetId: 'state.error').value;
      expect(running.busy, isTrue);
      expect(running.errorMessage, isNull);
      expect(await rerun, 'fixed');

      KitAction.dispose(widgetId: 'state.error');
    });

    test('falls back to the exception toString without a configured message',
        () async {
      final state = KitAction.state$(widgetId: 'state.raw');
      await expectLater(
        KitAction.run<String>(
          () async => throw Exception('raw failure'),
          widgetId: 'state.raw',
        ).execute(),
        throwsException,
      );
      expect(state.value.busy, isFalse);
      expect(state.value.errorMessage, 'Exception: raw failure');
      KitAction.dispose(widgetId: 'state.raw');
    });

    test('dispose closes the state subject', () async {
      final state = KitAction.state$(widgetId: 'state.dispose');
      expect(state.value.busy, isFalse);
      KitAction.dispose(widgetId: 'state.dispose');
      // A fresh state$ after dispose is a new idle subject.
      expect(KitAction.state$(widgetId: 'state.dispose').value.busy, isFalse);
      KitAction.dispose(widgetId: 'state.dispose');
    });
  });
}
