import 'package:appbox_kit_state/appbox_kit_state.dart';
import 'package:appbox_kit_state/appbox_kit_testing.dart';
import 'package:test/test.dart';

void main() {
  group('AppBoxKitState equality', () {
    test('same case and payload are equal', () {
      expect(const AppBoxKitSuccess<int>(5), const AppBoxKitSuccess<int>(5));
      expect(const AppBoxKitLoading<int>(0.5), const AppBoxKitLoading<int>(0.5));
      expect(const AppBoxKitIdle<int>(), const AppBoxKitIdle<int>());
      expect(
        const AppBoxKitError<int>(AppBoxKitFailure(code: 'x', message: 'm')),
        const AppBoxKitError<int>(AppBoxKitFailure(code: 'x', message: 'm')),
      );
    });

    test('different payloads are not equal', () {
      expect(const AppBoxKitSuccess<int>(5) == const AppBoxKitSuccess<int>(6), isFalse);
      expect(const AppBoxKitLoading<int>(0.1) == const AppBoxKitLoading<int>(0.2), isFalse);
    });
  });

  group('combinators', () {
    test('when folds the matching case', () {
      const AppBoxKitState<int> state = AppBoxKitSuccess(7);
      final label = state.when(
        idle: () => 'idle',
        pending: () => 'pending',
        loading: (p) => 'loading',
        success: (d) => 'success:$d',
        error: (f) => 'error',
      );
      expect(label, 'success:7');
    });

    test('dataOrNull / failureOrNull', () {
      expect(const AppBoxKitSuccess<int>(3).dataOrNull, 3);
      expect(const AppBoxKitIdle<int>().dataOrNull, isNull);
      expect(
        const AppBoxKitError<int>(AppBoxKitFailure(code: 'e', message: 'm')).failureOrNull?.code,
        'e',
      );
    });
  });

  group('transition guard', () {
    test('legal transition passes (idle -> loading)', () {
      final notifier = AppBoxKitStateNotifier<int>();
      notifier.emit(const AppBoxKitLoading<int>());
      expect(notifier.state, const AppBoxKitLoading<int>());
      notifier.dispose();
    });

    test('legal transition passes (success -> loading)', () {
      final notifier = AppBoxKitStateNotifier<int>(initial: const AppBoxKitSuccess(1));
      notifier.emit(const AppBoxKitLoading<int>());
      expect(notifier.state, const AppBoxKitLoading<int>());
      notifier.dispose();
    });

    test('illegal transition trips an assertion in debug (idle -> success)', () {
      final notifier = AppBoxKitStateNotifier<int>();
      expect(
        () => notifier.emit(const AppBoxKitSuccess<int>(1)),
        throwsA(isA<AssertionError>()),
      );
      notifier.dispose();
    });

    test('scripted notifier bypasses the guard', () {
      final notifier = AppBoxKitScriptedStateNotifier<int>();
      notifier.scriptAll(const [
        AppBoxKitSuccess<int>(1),
        AppBoxKitError<int>(AppBoxKitFailure(code: 'x', message: 'x')),
      ]);
      expect(
        notifier.state,
        const AppBoxKitError<int>(AppBoxKitFailure(code: 'x', message: 'x')),
      );
      notifier.dispose();
    });
  });

  group('track', () {
    test('drives loading -> success and returns the value', () async {
      final notifier = AppBoxKitStateNotifier<int>();
      final value = await notifier.track(Future.value(42));
      expect(value, 42);
      expect(notifier.state, const AppBoxKitSuccess<int>(42));
      notifier.dispose();
    });

    test('drives loading -> error on throw', () async {
      final notifier = AppBoxKitStateNotifier<int>();
      final value = await notifier.track(Future<int>.error(Exception('boom')));
      expect(value, isNull);
      expect(notifier.state.isError, isTrue);
      notifier.dispose();
    });
  });

  group('AppBoxKitStateRecorder', () {
    test('captures the emitted sequence with value equality', () async {
      final notifier = AppBoxKitStateNotifier<int>();
      final recorder = AppBoxKitStateRecorder<int>(notifier);
      notifier.emit(const AppBoxKitLoading<int>());
      notifier.emit(const AppBoxKitSuccess<int>(7));
      await Future<void>.delayed(Duration.zero);
      expect(recorder.states, const [
        AppBoxKitIdle<int>(),
        AppBoxKitLoading<int>(),
        AppBoxKitSuccess<int>(7),
      ]);
      await recorder.dispose();
      notifier.dispose();
    });
  });

  group('AppBoxKitRetryPolicy', () {
    test('delay curve grows by backoff and caps at maxDelay', () {
      const policy = AppBoxKitRetryPolicy(
        initialDelay: Duration(milliseconds: 100),
        backoffFactor: 2,
        maxDelay: Duration(milliseconds: 350),
      );
      expect(policy.delayForAttempt(1), Duration.zero);
      expect(policy.delayForAttempt(2), const Duration(milliseconds: 100));
      expect(policy.delayForAttempt(3), const Duration(milliseconds: 200));
      expect(policy.delayForAttempt(4), const Duration(milliseconds: 350));
    });
  });
}
