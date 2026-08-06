import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:appbox_kit_core/appbox_kit_locator.dart';
import 'package:appbox_kit_core/services/error/appbox_kit_error_service.dart';
import 'package:appbox_kit_ui_library/appbox_kit_testing.dart';
import 'package:appbox_kit_ui_library/utils/kit_action/appbox_kit_action.dart';
import 'package:appbox_kit_ui_library/utils/kit_action/appbox_kit_notification_type.dart';
import 'package:appbox_kit_ui_library/utils/kit_action/appbox_kit_action_pipeline.dart';

/// Behavior tests for the AppBoxKitActionPipeline — the app-level KitAction API
/// (hot dispatch + observation handles).
///
/// The observation-handle contract under test:
/// - dispatch ALWAYS executes (hot); the returned Future<R> observes the
///   already-running op — awaiting optional, dropping harmless.
/// - Guarded dispatches (same key in flight) complete with the in-flight
///   run's result, never an error.
/// - Debounce-superseded dispatches complete with the eventual run's result.
class _RecordingDialogService extends DialogService {
  final List<({String? title, String? description})> calls = [];

  @override
  Future<DialogResponse?> showDialog({
    String? title,
    String? description,
    String? cancelTitle,
    Color? cancelTitleColor,
    String buttonTitle = 'Ok',
    Color? buttonTitleColor,
    bool barrierDismissible = false,
    RouteSettings? routeSettings,
    GlobalKey<NavigatorState>? navigatorKey,
    DialogPlatform? dialogPlatform,
  }) {
    calls.add((title: title, description: description));
    return Future.value();
  }
}

class _RecordingBottomSheetService extends BottomSheetService {
  final List<({String title, String? description})> calls = [];

  @override
  Future<SheetResponse?> showBottomSheet({
    required String title,
    String? description,
    String confirmButtonTitle = 'Ok',
    String? cancelButtonTitle,
    bool enableDrag = true,
    bool barrierDismissible = true,
    bool isScrollControlled = false,
    Duration? exitBottomSheetDuration,
    Duration? enterBottomSheetDuration,
    bool? ignoreSafeArea,
    bool useRootNavigator = false,
    double elevation = 1,
  }) {
    calls.add((title: title, description: description));
    return Future.value();
  }
}

void main() {
  late FakeAppBoxKitNotificationService notifications;
  late _RecordingDialogService dialogs;
  late _RecordingBottomSheetService bottomSheets;

  setUp(() async {
    notifications = FakeAppBoxKitNotificationService();
    dialogs = _RecordingDialogService();
    bottomSheets = _RecordingBottomSheetService();
    appBoxKitLocator
      ..registerLazySingleton(() => Talker())
      ..registerLazySingleton(() => AppBoxKitErrorService())
      ..registerSingleton<AppBoxKitNotificationService>(notifications)
      ..registerSingleton<DialogService>(dialogs)
      ..registerSingleton<BottomSheetService>(bottomSheets);
    await appBoxKitLocator<AppBoxKitErrorService>().initialize();
  });

  tearDown(() => appBoxKitLocator.reset());

  AppBoxKitActionPipeline pipeline() =>
      AppBoxKitActionPipeline(owner: Object());

  group('kit.ui-library.action-pipeline — dispatch handles', () {
    test('dispatch executes hot and the handle completes with the result', () async {
      final p = pipeline();
      var ran = 0;
      final pipe = p.pipe<String, String>('op', (payload) async {
        ran++;
        return 'ran:$payload';
      });

      final handle = pipe.dispatch('x');
      // Hot: the run started on dispatch — no await of the handle needed.
      await pumpEventQueue();
      expect(ran, 1);
      expect(await handle, 'ran:x');
      p.dispose();
    });

    test('a dropped handle never surfaces an unhandled error', () async {
      final p = pipeline();
      final pipe = p.pipe<Null, String>('op', (_) async => throw 'boom');
      pipe.dispatch(null); // handle dropped, no fallback configured
      // If the handle's error were unhandled the test zone would fail here.
      await pumpEventQueue();
      p.dispose();
    });

    test('sequential dispatches both execute', () async {
      final p = pipeline();
      var runs = 0;
      final pipe = p.pipe<Null, String>('op', (_) async => 'run ${++runs}');
      expect(await pipe.dispatch(null), 'run 1');
      expect(await pipe.dispatch(null), 'run 2');
      p.dispose();
    });
  });

  group('kit.ui-library.action-pipeline — re-entry guard', () {
    test('a guarded dispatch handle completes with the in-flight result', () async {
      final p = pipeline();
      final gate = Completer<String>();
      var runs = 0;
      final pipe = p.pipe<String, String>('op', (payload) async {
        runs++;
        return gate.future;
      });

      final first = pipe.dispatch('a');
      final second = pipe.dispatch('b'); // same frame, run in flight
      gate.complete('shared');

      expect(await first, 'shared');
      expect(await second, 'shared',
          reason: 'the guarded handle observes the in-flight run');
      expect(runs, 1);
      p.dispose();
    });

    test('a guarded dispatch shares a fast run even when dispatched same-frame', () async {
      // Regression: async command delivery let a fast op complete before the
      // second command was processed, defeating the double-tap guard. The
      // sync command channel starts the run inside dispatch.
      final p = pipeline();
      var runs = 0;
      final pipe = p.pipe<Null, String>('op', (_) async {
        runs++;
        return 'fast';
      });

      final first = pipe.dispatch(null);
      final second = pipe.dispatch(null);
      expect(await first, 'fast');
      expect(await second, 'fast');
      expect(runs, 1);
      p.dispose();
    });

    test('the guard is keyed across pipes and one-shot runs of the same owner', () async {
      final p = pipeline();
      final gate = Completer<void>();
      var runs = 0;
      final pipe = p.pipe<Null, void>('op', (_) => gate.future);

      final viaPipe = pipe.dispatch(null);
      final viaRun = p.run<void>('op', () async {
        runs++;
      });
      gate.complete();
      await viaPipe;
      await viaRun;
      expect(runs, 0,
          reason: 'the one-shot run observed the pipe run already in flight');
      p.dispose();
    });
  });

  group('kit.ui-library.action-pipeline — debounce', () {
    test('superseded handles complete with the eventual run (last payload)', () async {
      final p = pipeline();
      final seen = <String>[];
      final pipe = p.pipe<String, String>(
        'op',
        (payload) async {
          seen.add(payload);
          return 'done:$payload';
        },
        debounce: const Duration(milliseconds: 50),
      );

      final h1 = pipe.dispatch('one');
      final h2 = pipe.dispatch('two');
      final h3 = pipe.dispatch('three');

      expect(await h1, 'done:three');
      expect(await h2, 'done:three');
      expect(await h3, 'done:three');
      expect(seen, ['three'],
          reason: 'debounce drops events, not callers — one run, last payload');
      p.dispose();
    });
  });

  group('kit.ui-library.action-pipeline — retry and timeout', () {
    test('retry re-runs the operation until success within maxAttempts', () async {
      final p = pipeline();
      var attempts = 0;
      final pipe = p.pipe<Null, String>(
        'op',
        (_) async {
          attempts++;
          if (attempts < 3) throw Exception('flake $attempts');
          return 'ok';
        },
        retry: (maxAttempts: 3, delay: null, shouldRetry: null),
      );

      expect(await pipe.dispatch(null), 'ok');
      expect(attempts, 3);
      p.dispose();
    });

    test('retry exhaustion routes the last failure into the error path', () async {
      final p = pipeline();
      var attempts = 0;
      final errors = <Object>[];
      final pipe = p.pipe<Null, String>(
        'op',
        (_) async {
          attempts++;
          throw Exception('always fails');
        },
        retry: (maxAttempts: 2, delay: null, shouldRetry: null),
        onError: errors.add,
      );

      await expectLater(pipe.dispatch(null), throwsException);
      expect(attempts, 2);
      expect(errors, hasLength(1), reason: 'onError taps once, on the final failure');
      p.dispose();
    });

    test('shouldRetry veto stops retrying immediately', () async {
      final p = pipeline();
      var attempts = 0;
      final pipe = p.pipe<Null, String>(
        'op',
        (_) async {
          attempts++;
          throw const FormatException('fatal');
        },
        retry: (
          maxAttempts: 5,
          delay: null,
          // Note: shouldRetry receives Exceptions — Error subtypes
          // (ArgumentError, StateError…) are wrapped first, builder parity.
          shouldRetry: (error) => error is! FormatException,
        ),
        errorMessage: 'failed',
        withValue: 'swallowed',
      );

      expect(await pipe.dispatch(null), 'swallowed',
          reason: 'errorMessage swallows with the fallback value');
      expect(attempts, 1);
      p.dispose();
    });

    test('timeout raises TimeoutException into the error path', () async {
      final p = pipeline();
      final errors = <Object>[];
      final pipe = p.pipe<Null, String>(
        'op',
        (_) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return 'late';
        },
        timeout: const Duration(milliseconds: 20),
        onError: errors.add,
      );

      await expectLater(pipe.dispatch(null), throwsA(isA<TimeoutException>()));
      expect(errors.single, isA<TimeoutException>());
      p.dispose();
    });
  });

  group('kit.ui-library.action-pipeline — error routing and notifications', () {
    test('errorMessage swallows with the fallback value', () async {
      final p = pipeline();
      final pipe = p.pipe<Null, String>(
        'op',
        (_) async => throw Exception('boom'),
        errorMessage: 'Op failed',
        withValue: 'fallback',
      );
      expect(await pipe.dispatch(null), 'fallback');
      p.dispose();
    });

    test('without errorMessage the handle completes with the original error', () async {
      final p = pipeline();
      final pipe = p.pipe<Null, String>(
        'op',
        (_) async => throw StateError('boom'),
      );
      await expectLater(pipe.dispatch(null), throwsA(isA<StateError>()));
      p.dispose();
    });

    test('error notification defaults to the snackbar kind', () async {
      final p = pipeline();
      final pipe = p.pipe<Null, void>(
        'op',
        (_) async => throw Exception('boom'),
        errorNotification: 'Could not save',
        errorMessage: 'Save failed',
      );
      await pipe.dispatch(null);
      expect(notifications.calls, hasLength(1));
      expect(notifications.calls.single.message, 'Could not save');
      expect(notifications.calls.single.kind, AppBoxKitNotificationKind.error);
      p.dispose();
    });

    test('error notification routes to dialog and bottomSheet kinds', () async {
      final p = pipeline();
      final dialogPipe = p.pipe<Null, void>(
        'dialogOp',
        (_) async => throw Exception('boom'),
        errorNotification: 'Dialog says no',
        errorNotificationType: AppBoxKitNotificationType.dialog,
        errorMessage: 'failed',
      );
      final sheetPipe = p.pipe<Null, void>(
        'sheetOp',
        (_) async => throw Exception('boom'),
        errorNotification: 'Sheet says no',
        errorNotificationType: AppBoxKitNotificationType.bottomSheet,
        errorMessage: 'failed',
      );

      await dialogPipe.dispatch(null);
      await sheetPipe.dispatch(null);

      expect(dialogs.calls.single.title, 'Error');
      expect(dialogs.calls.single.description, 'Dialog says no');
      expect(bottomSheets.calls.single.title, 'Error');
      expect(bottomSheets.calls.single.description, 'Sheet says no');
      expect(notifications.calls, isEmpty);
      p.dispose();
    });

    test('success notification fires on completion only', () async {
      final p = pipeline();
      final pipe = p.pipe<Null, String>(
        'op',
        (_) async => 'ok',
        successNotification: 'Saved',
      );
      await pipe.dispatch(null);
      expect(notifications.calls.single.message, 'Saved');
      expect(notifications.calls.single.kind, AppBoxKitNotificationKind.success);
      p.dispose();
    });

    test('state\$ carries busy transitions and the error identity', () async {
      final p = pipeline();
      final pipe = p.pipe<Null, void>(
        'op',
        (_) async => throw Exception('boom'),
        errorNotification: 'Snackbar message',
      );
      final states = <String>[];
      final sub = pipe.state$.listen(
          (state) => states.add('${state.busy}:${state.errorMessage}'));

      await expectLater(pipe.dispatch(null), throwsException);
      await pumpEventQueue();

      expect(states, [
        'false:null', // seed
        'true:null', // markBusy
        'true:Snackbar message', // markError (busy until markDone)
        'false:Snackbar message', // markDone keeps the message
      ]);
      await sub.cancel();
      p.dispose();
    });
  });

  group('kit.ui-library.action-pipeline — key sharing and dispose', () {
    test('pipe state shares the AppBoxKitAction registry key (deriveKey)', () async {
      final owner = Object();
      final p = AppBoxKitActionPipeline(owner: owner);
      // Bound via the builder-side entry point — one subject, one key.
      final builderSide = AppBoxKitAction.state$(owner: owner, name: 'op');
      final gate = Completer<void>();
      final pipe = p.pipe<Null, void>('op', (_) => gate.future);

      pipe.dispatch(null);
      expect(builderSide.value.busy, isTrue,
          reason: 'the pipe writes the same derived key actionState\$ reads');
      gate.complete();
      await pumpEventQueue();
      expect(builderSide.value.busy, isFalse);
      p.dispose();
    });

    test('dispatch after dispose drops silently and the handle reports it', () async {
      final p = pipeline();
      var runs = 0;
      final pipe = p.pipe<Null, void>('op', (_) async => runs++);
      p.dispose();

      final handle = pipe.dispatch(null);
      await expectLater(handle, throwsA(isA<StateError>()));
      await pumpEventQueue();
      expect(runs, 0);
    });

    test('dispose completes pending debounced handles and cancels the timer', () async {
      final p = pipeline();
      var runs = 0;
      final pipe = p.pipe<Null, void>(
        'op',
        (_) async => runs++,
        debounce: const Duration(seconds: 5),
      );
      final handle = pipe.dispatch(null);
      p.dispose();

      await expectLater(handle, throwsA(isA<StateError>()));
      await pumpEventQueue();
      expect(runs, 0, reason: 'the pending timer died with the pipeline');
    });

    test('an in-flight op runs to completion after dispose (cooperative-only)', () async {
      final p = pipeline();
      final gate = Completer<void>();
      var finished = false;
      final pipe = p.pipe<Null, void>('op', (_) async {
        await gate.future;
        finished = true;
      });
      final handle = pipe.dispatch(null);
      p.dispose();

      gate.complete();
      await handle;
      expect(finished, isTrue,
          reason: 'Dart futures cannot be aborted — dispose never kills a run');
    });
  });
}
