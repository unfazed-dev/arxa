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
import 'package:appbox_kit_ui_library/utils/kit_action/appbox_kit_action_bus.dart';

/// Behavior tests for the AppBoxKitActionBus — the app-level KitAction API
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

  AppBoxKitActionBus bus() =>
      AppBoxKitActionBus(owner: Object());

  group('kit.ui-library.action-bus — dispatch handles', () {
    test('dispatch executes hot and the handle completes with the result', () async {
      final p = bus();
      var ran = 0;
      final dispatcher = p.define<String, String>('op', (payload) async {
        ran++;
        return 'ran:$payload';
      });

      final handle = dispatcher.dispatch('x');
      // Hot: the run started on dispatch — no await of the handle needed.
      await pumpEventQueue();
      expect(ran, 1);
      expect(await handle, 'ran:x');
      p.dispose();
    });

    test('a dropped handle never surfaces an unhandled error', () async {
      final p = bus();
      final dispatcher = p.define<Null, String>('op', (_) async => throw 'boom');
      dispatcher.dispatch(null); // handle dropped, no fallback configured
      // If the handle's error were unhandled the test zone would fail here.
      await pumpEventQueue();
      p.dispose();
    });

    test('sequential dispatches both execute', () async {
      final p = bus();
      var runs = 0;
      final dispatcher = p.define<Null, String>('op', (_) async => 'run ${++runs}');
      expect(await dispatcher.dispatch(null), 'run 1');
      expect(await dispatcher.dispatch(null), 'run 2');
      p.dispose();
    });
  });

  group('kit.ui-library.action-bus — re-entry guard', () {
    test('a guarded dispatch handle completes with the in-flight result', () async {
      final p = bus();
      final gate = Completer<String>();
      var runs = 0;
      final dispatcher = p.define<String, String>('op', (payload) async {
        runs++;
        return gate.future;
      });

      final first = dispatcher.dispatch('a');
      final second = dispatcher.dispatch('b'); // same frame, run in flight
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
      final p = bus();
      var runs = 0;
      final dispatcher = p.define<Null, String>('op', (_) async {
        runs++;
        return 'fast';
      });

      final first = dispatcher.dispatch(null);
      final second = dispatcher.dispatch(null);
      expect(await first, 'fast');
      expect(await second, 'fast');
      expect(runs, 1);
      p.dispose();
    });

    test('the guard is keyed across dispatchers and one-shot runs of the same owner', () async {
      final p = bus();
      final gate = Completer<void>();
      var runs = 0;
      final dispatcher = p.define<Null, void>('op', (_) => gate.future);

      final viaPipe = dispatcher.dispatch(null);
      final viaRun = p.run<void>('op', () async {
        runs++;
      });
      gate.complete();
      await viaPipe;
      await viaRun;
      expect(runs, 0,
          reason: 'the one-shot run observed the dispatcher run already in flight');
      p.dispose();
    });
  });

  group('kit.ui-library.action-bus — debounce', () {
    test('superseded handles complete with the eventual run (last payload)', () async {
      final p = bus();
      final seen = <String>[];
      final dispatcher = p.define<String, String>(
        'op',
        (payload) async {
          seen.add(payload);
          return 'done:$payload';
        },
        debounce: const Duration(milliseconds: 50),
      );

      final h1 = dispatcher.dispatch('one');
      final h2 = dispatcher.dispatch('two');
      final h3 = dispatcher.dispatch('three');

      expect(await h1, 'done:three');
      expect(await h2, 'done:three');
      expect(await h3, 'done:three');
      expect(seen, ['three'],
          reason: 'debounce drops events, not callers — one run, last payload');
      p.dispose();
    });
  });

  group('kit.ui-library.action-bus — retry and timeout', () {
    test('retry re-runs the operation until success within maxAttempts', () async {
      final p = bus();
      var attempts = 0;
      final dispatcher = p.define<Null, String>(
        'op',
        (_) async {
          attempts++;
          if (attempts < 3) throw Exception('flake $attempts');
          return 'ok';
        },
        retry: (maxAttempts: 3, delay: null, shouldRetry: null),
      );

      expect(await dispatcher.dispatch(null), 'ok');
      expect(attempts, 3);
      p.dispose();
    });

    test('retry exhaustion routes the last failure into the error path', () async {
      final p = bus();
      var attempts = 0;
      final errors = <Object>[];
      final dispatcher = p.define<Null, String>(
        'op',
        (_) async {
          attempts++;
          throw Exception('always fails');
        },
        retry: (maxAttempts: 2, delay: null, shouldRetry: null),
        onError: errors.add,
      );

      await expectLater(dispatcher.dispatch(null), throwsException);
      expect(attempts, 2);
      expect(errors, hasLength(1), reason: 'onError taps once, on the final failure');
      p.dispose();
    });

    test('shouldRetry veto stops retrying immediately', () async {
      final p = bus();
      var attempts = 0;
      final dispatcher = p.define<Null, String>(
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

      expect(await dispatcher.dispatch(null), 'swallowed',
          reason: 'errorMessage swallows with the fallback value');
      expect(attempts, 1);
      p.dispose();
    });

    test('timeout raises TimeoutException into the error path', () async {
      final p = bus();
      final errors = <Object>[];
      final dispatcher = p.define<Null, String>(
        'op',
        (_) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return 'late';
        },
        timeout: const Duration(milliseconds: 20),
        onError: errors.add,
      );

      await expectLater(dispatcher.dispatch(null), throwsA(isA<TimeoutException>()));
      expect(errors.single, isA<TimeoutException>());
      p.dispose();
    });
  });

  group('kit.ui-library.action-bus — error routing and notifications', () {
    test('errorMessage swallows with the fallback value', () async {
      final p = bus();
      final dispatcher = p.define<Null, String>(
        'op',
        (_) async => throw Exception('boom'),
        errorMessage: 'Op failed',
        withValue: 'fallback',
      );
      expect(await dispatcher.dispatch(null), 'fallback');
      p.dispose();
    });

    test('without errorMessage the handle completes with the original error', () async {
      final p = bus();
      final dispatcher = p.define<Null, String>(
        'op',
        (_) async => throw StateError('boom'),
      );
      await expectLater(dispatcher.dispatch(null), throwsA(isA<StateError>()));
      p.dispose();
    });

    test('error notification defaults to the snackbar kind', () async {
      final p = bus();
      final dispatcher = p.define<Null, void>(
        'op',
        (_) async => throw Exception('boom'),
        errorNotification: 'Could not save',
        errorMessage: 'Save failed',
      );
      await dispatcher.dispatch(null);
      expect(notifications.calls, hasLength(1));
      expect(notifications.calls.single.message, 'Could not save');
      expect(notifications.calls.single.kind, AppBoxKitNotificationKind.error);
      p.dispose();
    });

    test('error notification routes to dialog and bottomSheet kinds', () async {
      final p = bus();
      final dialogPipe = p.define<Null, void>(
        'dialogOp',
        (_) async => throw Exception('boom'),
        errorNotification: 'Dialog says no',
        errorNotificationType: AppBoxKitNotificationType.dialog,
        errorMessage: 'failed',
      );
      final sheetPipe = p.define<Null, void>(
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
      final p = bus();
      final dispatcher = p.define<Null, String>(
        'op',
        (_) async => 'ok',
        successNotification: 'Saved',
      );
      await dispatcher.dispatch(null);
      expect(notifications.calls.single.message, 'Saved');
      expect(notifications.calls.single.kind, AppBoxKitNotificationKind.success);
      p.dispose();
    });

    test('state\$ carries busy transitions and the error identity', () async {
      final p = bus();
      final dispatcher = p.define<Null, void>(
        'op',
        (_) async => throw Exception('boom'),
        errorNotification: 'Snackbar message',
      );
      final states = <String>[];
      final sub = dispatcher.state$.listen(
          (state) => states.add('${state.busy}:${state.errorMessage}'));

      await expectLater(dispatcher.dispatch(null), throwsException);
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

  group('kit.ui-library.action-bus — key sharing and dispose', () {
    test('dispatcher state shares the AppBoxKitAction registry key (deriveKey)', () async {
      final owner = Object();
      final p = AppBoxKitActionBus(owner: owner);
      // Bound via the builder-side entry point — one subject, one key.
      final builderSide = AppBoxKitAction.state$(owner: owner, name: 'op');
      final gate = Completer<void>();
      final dispatcher = p.define<Null, void>('op', (_) => gate.future);

      dispatcher.dispatch(null);
      expect(builderSide.value.busy, isTrue,
          reason: 'the dispatcher writes the same derived key actionState\$ reads');
      gate.complete();
      await pumpEventQueue();
      expect(builderSide.value.busy, isFalse);
      p.dispose();
    });

    test('dispatch after dispose drops silently and the handle reports it', () async {
      final p = bus();
      var runs = 0;
      final dispatcher = p.define<Null, void>('op', (_) async => runs++);
      p.dispose();

      final handle = dispatcher.dispatch(null);
      await expectLater(handle, throwsA(isA<StateError>()));
      await pumpEventQueue();
      expect(runs, 0);
    });

    test('dispose completes pending debounced handles and cancels the timer', () async {
      final p = bus();
      var runs = 0;
      final dispatcher = p.define<Null, void>(
        'op',
        (_) async => runs++,
        debounce: const Duration(seconds: 5),
      );
      final handle = dispatcher.dispatch(null);
      p.dispose();

      await expectLater(handle, throwsA(isA<StateError>()));
      await pumpEventQueue();
      expect(runs, 0, reason: 'the pending timer died with the bus');
    });

    test('an in-flight op runs to completion after dispose (cooperative-only)', () async {
      final p = bus();
      final gate = Completer<void>();
      var finished = false;
      final dispatcher = p.define<Null, void>('op', (_) async {
        await gate.future;
        finished = true;
      });
      final handle = dispatcher.dispatch(null);
      p.dispose();

      gate.complete();
      await handle;
      expect(finished, isTrue,
          reason: 'Dart futures cannot be aborted — dispose never kills a run');
    });

    test('flushOnDispose executes a pending debounced dispatch immediately', () async {
      final p = bus();
      final seen = <String>[];
      final dispatcher = p.define<String, String>(
        'op',
        (payload) async {
          seen.add(payload);
          return 'saved:$payload';
        },
        debounce: const Duration(seconds: 5),
        flushOnDispose: true,
      );
      final handle = dispatcher.dispatch('final draft');

      await p.dispose(); // awaits the flush

      expect(seen, ['final draft'],
          reason: 'dispose flushes instead of dropping the pending save');
      expect(await handle, 'saved:final draft');
    });

    test('flushOnDispose attaches to an in-flight run (guard semantics)', () async {
      final p = bus();
      final gate = Completer<String>();
      final debouncedRuns = <String>[];
      final dispatcher = p.define<String, String>(
        'op',
        (payload) async {
          debouncedRuns.add(payload);
          return 'debounced:$payload';
        },
        debounce: const Duration(seconds: 5),
        flushOnDispose: true,
      );
      // A non-debounced run on the same key is in flight when dispose hits.
      final inFlight = p.run<String>('op', () => gate.future);
      final pending = dispatcher.dispatch('dropped payload');

      final disposeDone = p.dispose();
      gate.complete('in-flight result');
      await disposeDone;

      expect(await pending, 'in-flight result',
          reason: 'the flush queues per guard semantics, it never re-runs');
      expect(await inFlight, 'in-flight result');
      expect(debouncedRuns, isEmpty);
    });
  });

  group('kit.ui-library.action-bus — throttle and parallel execution', () {
    test('throttle is leading-edge: dispatches inside the window share the run', () async {
      final p = bus();
      var runs = 0;
      final dispatcher = p.define<String, String>(
        'op',
        (payload) async {
          runs++;
          return 'ran:$payload';
        },
        throttle: const Duration(milliseconds: 150),
      );

      final first = dispatcher.dispatch('one');
      final second = dispatcher.dispatch('two'); // inside the window
      expect(await first, 'ran:one');
      expect(await second, 'ran:one',
          reason: 'throttled-away handle observes the previous run');
      expect(runs, 1);

      // After the window the next dispatch runs again.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await dispatcher.dispatch('three'), 'ran:three');
      expect(runs, 2);
      p.dispose();
    });

    test('throttle window anchors at the run start (builder parity)', () async {
      final p = bus();
      final gate = Completer<String>();
      var runs = 0;
      final dispatcher = p.define<Null, String>(
        'op',
        (_) async {
          runs++;
          return gate.future;
        },
        throttle: const Duration(seconds: 30),
      );

      final first = dispatcher.dispatch(null);
      final second = dispatcher.dispatch(null); // in flight, inside the window
      gate.complete('shared');
      expect(await first, 'shared');
      expect(await second, 'shared',
          reason: 'a throttled dispatch attaches to the in-flight run');
      expect(runs, 1);
      p.dispose();
    });

    test('parallelExecution opts out of the guard — every dispatch runs', () async {
      final p = bus();
      final gate = Completer<void>();
      var runs = 0;
      final dispatcher = p.define<String, String>(
        'op',
        (payload) async {
          runs++;
          await gate.future;
          return 'own:$payload';
        },
        parallelExecution: true,
      );

      final first = dispatcher.dispatch('a');
      final second = dispatcher.dispatch('b');
      await pumpEventQueue();
      expect(runs, 2, reason: 'flatMap — no in-flight sharing');
      gate.complete();
      expect(await first, 'own:a');
      expect(await second, 'own:b',
          reason: 'each handle gets its own run’s result');
      p.dispose();
    });
  });

  group('kit.ui-library.action-bus — success and loading taps', () {
    test('onSuccess runs after the op and before the handle completes', () async {
      final p = bus();
      final order = <String>[];
      final dispatcher = p.define<Null, String>(
        'op',
        (_) async => 'result',
        onSuccess: (result) => order.add('tap:$result'),
      );

      final handle = dispatcher.dispatch(null).then((result) {
        order.add('handle:$result');
        return result;
      });

      expect(await handle, 'result');
      expect(order, ['tap:result', 'handle:result']);
      p.dispose();
    });

    test('an onSuccess tap error logs a warning and never fails the run', () async {
      final p = bus();
      final dispatcher = p.define<Null, String>(
        'op',
        (_) async => 'result',
        onSuccess: (_) => throw Exception('tap exploded'),
      );
      expect(await dispatcher.dispatch(null), 'result');
      p.dispose();
    });

    test('loading notification fires at run start', () async {
      final p = bus();
      final gate = Completer<String>();
      final dispatcher = p.define<Null, String>(
        'op',
        (_) => gate.future,
        loadingNotification: 'Working…',
      );
      dispatcher.dispatch(null);
      expect(notifications.calls.single.message, 'Working…');
      expect(notifications.calls.single.kind, AppBoxKitNotificationKind.info,
          reason: 'shown while the op is still in flight');
      gate.complete('done');
      await pumpEventQueue();
      p.dispose();
    });
  });
}
