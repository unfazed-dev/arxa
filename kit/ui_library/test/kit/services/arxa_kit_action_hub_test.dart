import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_core/services/error/arxa_kit_error_service.dart';
import 'package:arxa_kit_ui_library/arxa_kit_testing.dart';
import 'package:arxa_kit_ui_library/utils/kit_action/arxa_kit_action.dart';
import 'package:arxa_kit_ui_library/utils/kit_action/arxa_kit_notification_type.dart';
import 'package:arxa_kit_ui_library/utils/kit_action/arxa_kit_action_hub.dart';

/// Behavior tests for the ArxaKitActionHub — the app-level KitAction API
/// (hot send + observation handles).
///
/// The observation-handle contract under test:
/// - send ALWAYS executes (hot); the returned Future<R> observes the
///   already-running op — awaiting optional, dropping harmless.
/// - Guarded dispatches (same key in flight) complete with the in-flight
///   run's result, never an error.
/// - Debounce-superseded dispatches complete with the eventual run's result.
void main() {
  late FakeArxaKitNotificationService notifications;

  setUp(() async {
    notifications = FakeArxaKitNotificationService();
    arxaKitLocator
      ..registerLazySingleton(() => Talker())
      ..registerLazySingleton(() => ArxaKitErrorService())
      ..registerSingleton<ArxaKitNotificationService>(notifications);
    await arxaKitLocator<ArxaKitErrorService>().initialize();
  });

  tearDown(() => arxaKitLocator.reset());

  ArxaKitActionHub hub() => ArxaKitActionHub(owner: Object());

  group('kit.ui-library.action-hub — send handles', () {
    test('send executes hot and the handle completes with the result',
        () async {
      final p = hub();
      var ran = 0;
      final command = p.on<String, String>('op', (payload) async {
        ran++;
        return 'ran:$payload';
      });

      final handle = command.send('x');
      // Hot: the run started on send — no await of the handle needed.
      await pumpEventQueue();
      expect(ran, 1);
      expect(await handle, 'ran:x');
      p.dispose();
    });

    test('a dropped handle never surfaces an unhandled error', () async {
      final p = hub();
      final command = p.on<Null, String>('op', (_) async => throw 'boom');
      command.send(null); // handle dropped, no fallback configured
      // If the handle's error were unhandled the test zone would fail here.
      await pumpEventQueue();
      p.dispose();
    });

    test('sequential dispatches both execute', () async {
      final p = hub();
      var runs = 0;
      final command = p.on<Null, String>('op', (_) async => 'run ${++runs}');
      expect(await command.send(null), 'run 1');
      expect(await command.send(null), 'run 2');
      p.dispose();
    });
  });

  group('kit.ui-library.action-hub — re-entry guard', () {
    test('a guarded send handle completes with the in-flight result', () async {
      final p = hub();
      final gate = Completer<String>();
      var runs = 0;
      final command = p.on<String, String>('op', (payload) async {
        runs++;
        return gate.future;
      });

      final first = command.send('a');
      final second = command.send('b'); // same frame, run in flight
      gate.complete('shared');

      expect(await first, 'shared');
      expect(await second, 'shared',
          reason: 'the guarded handle observes the in-flight run');
      expect(runs, 1);
      p.dispose();
    });

    test('a guarded send shares a fast run even when dispatched same-frame',
        () async {
      // Regression: async command delivery let a fast op complete before the
      // second command was processed, defeating the double-tap guard. The
      // sync command channel starts the run inside send.
      final p = hub();
      var runs = 0;
      final command = p.on<Null, String>('op', (_) async {
        runs++;
        return 'fast';
      });

      final first = command.send(null);
      final second = command.send(null);
      expect(await first, 'fast');
      expect(await second, 'fast');
      expect(runs, 1);
      p.dispose();
    });

    test(
        'the guard is keyed across commands and one-shot runs of the same owner',
        () async {
      final p = hub();
      final gate = Completer<void>();
      var runs = 0;
      final command = p.on<Null, void>('op', (_) => gate.future);

      final viaPipe = command.send(null);
      final viaRun = p.send<void>('op', () async {
        runs++;
      });
      gate.complete();
      await viaPipe;
      await viaRun;
      expect(runs, 0,
          reason:
              'the one-shot run observed the command run already in flight');
      p.dispose();
    });
  });

  group('kit.ui-library.action-hub — debounce', () {
    test('superseded handles complete with the eventual run (last payload)',
        () async {
      final p = hub();
      final seen = <String>[];
      final command = p.on<String, String>(
        'op',
        (payload) async {
          seen.add(payload);
          return 'done:$payload';
        },
        debounce: const Duration(milliseconds: 50),
      );

      final h1 = command.send('one');
      final h2 = command.send('two');
      final h3 = command.send('three');

      expect(await h1, 'done:three');
      expect(await h2, 'done:three');
      expect(await h3, 'done:three');
      expect(seen, ['three'],
          reason: 'debounce drops events, not callers — one run, last payload');
      p.dispose();
    });
  });

  group('kit.ui-library.action-hub — retry and timeout', () {
    test('retry re-runs the operation until success within maxAttempts',
        () async {
      final p = hub();
      var attempts = 0;
      final command = p.on<Null, String>(
        'op',
        (_) async {
          attempts++;
          if (attempts < 3) throw Exception('flake $attempts');
          return 'ok';
        },
        retry: (maxAttempts: 3, delay: null, shouldRetry: null),
      );

      expect(await command.send(null), 'ok');
      expect(attempts, 3);
      p.dispose();
    });

    test('retry exhaustion routes the last failure into the error path',
        () async {
      final p = hub();
      var attempts = 0;
      final errors = <Object>[];
      final command = p.on<Null, String>(
        'op',
        (_) async {
          attempts++;
          throw Exception('always fails');
        },
        retry: (maxAttempts: 2, delay: null, shouldRetry: null),
        onError: errors.add,
      );

      await expectLater(command.send(null), throwsException);
      expect(attempts, 2);
      expect(errors, hasLength(1),
          reason: 'onError taps once, on the final failure');
      p.dispose();
    });

    test('shouldRetry veto stops retrying immediately', () async {
      final p = hub();
      var attempts = 0;
      final command = p.on<Null, String>(
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

      expect(await command.send(null), 'swallowed',
          reason: 'errorMessage swallows with the fallback value');
      expect(attempts, 1);
      p.dispose();
    });

    test('timeout raises TimeoutException into the error path', () async {
      final p = hub();
      final errors = <Object>[];
      final command = p.on<Null, String>(
        'op',
        (_) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return 'late';
        },
        timeout: const Duration(milliseconds: 20),
        onError: errors.add,
      );

      await expectLater(command.send(null), throwsA(isA<TimeoutException>()));
      expect(errors.single, isA<TimeoutException>());
      p.dispose();
    });
  });

  group('kit.ui-library.action-hub — error routing and notifications', () {
    test('errorMessage swallows with the fallback value', () async {
      final p = hub();
      final command = p.on<Null, String>(
        'op',
        (_) async => throw Exception('boom'),
        errorMessage: 'Op failed',
        withValue: 'fallback',
      );
      expect(await command.send(null), 'fallback');
      p.dispose();
    });

    test('without errorMessage the handle completes with the original error',
        () async {
      final p = hub();
      final command = p.on<Null, String>(
        'op',
        (_) async => throw StateError('boom'),
      );
      await expectLater(command.send(null), throwsA(isA<StateError>()));
      p.dispose();
    });

    test('error notification defaults to the snackbar kind', () async {
      final p = hub();
      final command = p.on<Null, void>(
        'op',
        (_) async => throw Exception('boom'),
        errorNotification: 'Could not save',
        errorMessage: 'Save failed',
      );
      await command.send(null);
      expect(notifications.calls, hasLength(1));
      expect(notifications.calls.single.message, 'Could not save');
      expect(notifications.calls.single.kind, ArxaKitNotificationKind.error);
      p.dispose();
    });

    test('confirm gate: a decline never runs the op, an accept runs it once',
        () async {
      final p = hub();
      var ran = 0;
      final command = p.on<Null, void>(
        'guarded',
        (_) async => ran++,
        confirmTitle: 'Delete?',
        confirmActionLabel: 'Delete',
        confirmDestructive: true,
      );

      // declined (the fake's confirmResult defaults to false) — the op never
      // runs and the handle still completes.
      await command.send(null);
      expect(ran, 0);
      expect(notifications.confirmCalls.single.title, 'Delete?');

      // accepted.
      notifications.confirmResult = true;
      await command.send(null);
      expect(ran, 1);
      p.dispose();
    });

    test('error notification routes to dialog and bottomSheet kinds', () async {
      final p = hub();
      final dialogPipe = p.on<Null, void>(
        'dialogOp',
        (_) async => throw Exception('boom'),
        errorNotification: 'Dialog says no',
        errorNotificationType: ArxaKitNotificationType.dialog,
        errorMessage: 'failed',
      );
      final sheetPipe = p.on<Null, void>(
        'sheetOp',
        (_) async => throw Exception('boom'),
        errorNotification: 'Sheet says no',
        errorNotificationType: ArxaKitNotificationType.bottomSheet,
        errorMessage: 'failed',
      );

      await dialogPipe.send(null);
      await sheetPipe.send(null);

      // Both kinds route through ArxaKitNotificationService's kit-rendered
      // ask-surfaces (alert / notice) — never stacked's DialogService /
      // BottomSheetService directly.
      expect(notifications.alertCalls.single.title, 'Error');
      expect(notifications.alertCalls.single.message, 'Dialog says no');
      expect(notifications.noticeCalls.single.title, 'Error');
      expect(notifications.noticeCalls.single.message, 'Sheet says no');
      expect(notifications.calls, isEmpty);
      p.dispose();
    });

    test('success notification fires on completion only', () async {
      final p = hub();
      final command = p.on<Null, String>(
        'op',
        (_) async => 'ok',
        successNotification: 'Saved',
      );
      await command.send(null);
      expect(notifications.calls.single.message, 'Saved');
      expect(
          notifications.calls.single.kind, ArxaKitNotificationKind.success);
      p.dispose();
    });

    test('state\$ carries busy transitions and the error identity', () async {
      final p = hub();
      final command = p.on<Null, void>(
        'op',
        (_) async => throw Exception('boom'),
        errorNotification: 'Snackbar message',
      );
      final states = <String>[];
      final sub = command.state$
          .listen((state) => states.add('${state.busy}:${state.errorMessage}'));

      await expectLater(command.send(null), throwsException);
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

  group('kit.ui-library.action-hub — key sharing and dispose', () {
    test('command state shares the ArxaKitAction registry key (deriveKey)',
        () async {
      final owner = Object();
      final p = ArxaKitActionHub(owner: owner);
      // Bound via the builder-side entry point — one subject, one key.
      final builderSide = ArxaKitAction.state$(owner: owner, name: 'op');
      final gate = Completer<void>();
      final command = p.on<Null, void>('op', (_) => gate.future);

      command.send(null);
      expect(builderSide.value.busy, isTrue,
          reason:
              'the command writes the same derived key actionState\$ reads');
      gate.complete();
      await pumpEventQueue();
      expect(builderSide.value.busy, isFalse);
      p.dispose();
    });

    test('send after dispose drops silently and the handle reports it',
        () async {
      final p = hub();
      var runs = 0;
      final command = p.on<Null, void>('op', (_) async => runs++);
      p.dispose();

      final handle = command.send(null);
      await expectLater(handle, throwsA(isA<StateError>()));
      await pumpEventQueue();
      expect(runs, 0);
    });

    test('dispose completes pending debounced handles and cancels the timer',
        () async {
      final p = hub();
      var runs = 0;
      final command = p.on<Null, void>(
        'op',
        (_) async => runs++,
        debounce: const Duration(seconds: 5),
      );
      final handle = command.send(null);
      p.dispose();

      await expectLater(handle, throwsA(isA<StateError>()));
      await pumpEventQueue();
      expect(runs, 0, reason: 'the pending timer died with the hub');
    });

    test('an in-flight op runs to completion after dispose (cooperative-only)',
        () async {
      final p = hub();
      final gate = Completer<void>();
      var finished = false;
      final command = p.on<Null, void>('op', (_) async {
        await gate.future;
        finished = true;
      });
      final handle = command.send(null);
      p.dispose();

      gate.complete();
      await handle;
      expect(finished, isTrue,
          reason: 'Dart futures cannot be aborted — dispose never kills a run');
    });

    test('flushOnDispose executes a pending debounced send immediately',
        () async {
      final p = hub();
      final seen = <String>[];
      final command = p.on<String, String>(
        'op',
        (payload) async {
          seen.add(payload);
          return 'saved:$payload';
        },
        debounce: const Duration(seconds: 5),
        flushOnDispose: true,
      );
      final handle = command.send('final draft');

      await p.dispose(); // awaits the flush

      expect(seen, ['final draft'],
          reason: 'dispose flushes instead of dropping the pending save');
      expect(await handle, 'saved:final draft');
    });

    test('flushOnDispose attaches to an in-flight run (guard semantics)',
        () async {
      final p = hub();
      final gate = Completer<String>();
      final debouncedRuns = <String>[];
      final command = p.on<String, String>(
        'op',
        (payload) async {
          debouncedRuns.add(payload);
          return 'debounced:$payload';
        },
        debounce: const Duration(seconds: 5),
        flushOnDispose: true,
      );
      // A non-debounced run on the same key is in flight when dispose hits.
      final inFlight = p.send<String>('op', () => gate.future);
      final pending = command.send('dropped payload');

      final disposeDone = p.dispose();
      gate.complete('in-flight result');
      await disposeDone;

      expect(await pending, 'in-flight result',
          reason: 'the flush queues per guard semantics, it never re-runs');
      expect(await inFlight, 'in-flight result');
      expect(debouncedRuns, isEmpty);
    });
  });

  group('kit.ui-library.action-hub — throttle and parallel execution', () {
    test('throttle is leading-edge: dispatches inside the window share the run',
        () async {
      final p = hub();
      var runs = 0;
      final command = p.on<String, String>(
        'op',
        (payload) async {
          runs++;
          return 'ran:$payload';
        },
        throttle: const Duration(milliseconds: 150),
      );

      final first = command.send('one');
      final second = command.send('two'); // inside the window
      expect(await first, 'ran:one');
      expect(await second, 'ran:one',
          reason: 'throttled-away handle observes the previous run');
      expect(runs, 1);

      // After the window the next send runs again.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await command.send('three'), 'ran:three');
      expect(runs, 2);
      p.dispose();
    });

    test('throttle window anchors at the run start (builder parity)', () async {
      final p = hub();
      final gate = Completer<String>();
      var runs = 0;
      final command = p.on<Null, String>(
        'op',
        (_) async {
          runs++;
          return gate.future;
        },
        throttle: const Duration(seconds: 30),
      );

      final first = command.send(null);
      final second = command.send(null); // in flight, inside the window
      gate.complete('shared');
      expect(await first, 'shared');
      expect(await second, 'shared',
          reason: 'a throttled send attaches to the in-flight run');
      expect(runs, 1);
      p.dispose();
    });

    test('parallelExecution opts out of the guard — every send runs', () async {
      final p = hub();
      final gate = Completer<void>();
      var runs = 0;
      final command = p.on<String, String>(
        'op',
        (payload) async {
          runs++;
          await gate.future;
          return 'own:$payload';
        },
        parallelExecution: true,
      );

      final first = command.send('a');
      final second = command.send('b');
      await pumpEventQueue();
      expect(runs, 2, reason: 'flatMap — no in-flight sharing');
      gate.complete();
      expect(await first, 'own:a');
      expect(await second, 'own:b',
          reason: 'each handle gets its own run’s result');
      p.dispose();
    });
  });

  group('kit.ui-library.action-hub — success and loading taps', () {
    test('onSuccess runs after the op and before the handle completes',
        () async {
      final p = hub();
      final order = <String>[];
      final command = p.on<Null, String>(
        'op',
        (_) async => 'result',
        onSuccess: (result) => order.add('tap:$result'),
      );

      final handle = command.send(null).then((result) {
        order.add('handle:$result');
        return result;
      });

      expect(await handle, 'result');
      expect(order, ['tap:result', 'handle:result']);
      p.dispose();
    });

    test('an onSuccess tap error logs a warning and never fails the run',
        () async {
      final p = hub();
      final command = p.on<Null, String>(
        'op',
        (_) async => 'result',
        onSuccess: (_) => throw Exception('tap exploded'),
      );
      expect(await command.send(null), 'result');
      p.dispose();
    });

    test('loading notification fires at run start', () async {
      final p = hub();
      final gate = Completer<String>();
      final command = p.on<Null, String>(
        'op',
        (_) => gate.future,
        loadingNotification: 'Working…',
      );
      command.send(null);
      expect(notifications.calls.single.message, 'Working…');
      expect(notifications.calls.single.kind, ArxaKitNotificationKind.info,
          reason: 'shown while the op is still in flight');
      gate.complete('done');
      await pumpEventQueue();
      p.dispose();
    });
  });
}
