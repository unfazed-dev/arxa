import 'package:arxa_kit_state/arxa_kit_state.dart';
import 'package:arxa_kit_state/arxa_kit_testing.dart';
import 'package:test/test.dart';

void main() {
  group('ArxaKitState equality', () {
    test('kit.state.equality — same case and payload are equal', () {
      expect(const ArxaKitSuccess<int>(5), const ArxaKitSuccess<int>(5));
      expect(const ArxaKitLoading<int>(0.5), const ArxaKitLoading<int>(0.5));
      expect(const ArxaKitIdle<int>(), const ArxaKitIdle<int>());
      expect(
        const ArxaKitError<int>(ArxaKitFailure(code: 'x', message: 'm')),
        const ArxaKitError<int>(ArxaKitFailure(code: 'x', message: 'm')),
      );
    });

    test('kit.state.equality — different payloads are not equal', () {
      expect(const ArxaKitSuccess<int>(5) == const ArxaKitSuccess<int>(6), isFalse);
      expect(const ArxaKitLoading<int>(0.1) == const ArxaKitLoading<int>(0.2), isFalse);
    });
  });

  group('combinators', () {
    test('kit.state.combinators — when folds the matching case', () {
      const ArxaKitState<int> state = ArxaKitSuccess(7);
      final label = state.when(
        idle: () => 'idle',
        pending: () => 'pending',
        loading: (p) => 'loading',
        success: (d) => 'success:$d',
        error: (f) => 'error',
      );
      expect(label, 'success:7');
    });

    test('kit.state.combinators — dataOrNull / failureOrNull expose the payload of the matching case', () {
      expect(const ArxaKitSuccess<int>(3).dataOrNull, 3);
      expect(const ArxaKitIdle<int>().dataOrNull, isNull);
      expect(
        const ArxaKitError<int>(ArxaKitFailure(code: 'e', message: 'm')).failureOrNull?.code,
        'e',
      );
    });
  });

  group('transition guard', () {
    test('kit.state.transitions — legal transition passes (idle -> loading)', () {
      final notifier = ArxaKitStateNotifier<int>();
      notifier.emit(const ArxaKitLoading<int>());
      expect(notifier.state, const ArxaKitLoading<int>());
      notifier.dispose();
    });

    test('kit.state.transitions — legal transition passes (success -> loading)', () {
      final notifier = ArxaKitStateNotifier<int>(initial: const ArxaKitSuccess(1));
      notifier.emit(const ArxaKitLoading<int>());
      expect(notifier.state, const ArxaKitLoading<int>());
      notifier.dispose();
    });

    test('kit.state.transitions — illegal transition trips an assertion in debug (idle -> success)', () {
      final notifier = ArxaKitStateNotifier<int>();
      expect(
        () => notifier.emit(const ArxaKitSuccess<int>(1)),
        throwsA(isA<AssertionError>()),
      );
      notifier.dispose();
    });

    test('kit.state.transitions — scripted notifier bypasses the guard', () {
      final notifier = ArxaKitScriptedStateNotifier<int>();
      notifier.scriptAll(const [
        ArxaKitSuccess<int>(1),
        ArxaKitError<int>(ArxaKitFailure(code: 'x', message: 'x')),
      ]);
      expect(
        notifier.state,
        const ArxaKitError<int>(ArxaKitFailure(code: 'x', message: 'x')),
      );
      notifier.dispose();
    });
  });

  group('track', () {
    test('kit.state.track — drives loading -> success and returns the value', () async {
      final notifier = ArxaKitStateNotifier<int>();
      final value = await notifier.track(Future.value(42));
      expect(value, 42);
      expect(notifier.state, const ArxaKitSuccess<int>(42));
      notifier.dispose();
    });

    test('kit.state.track — drives loading -> error on throw', () async {
      final notifier = ArxaKitStateNotifier<int>();
      final value = await notifier.track(Future<int>.error(Exception('boom')));
      expect(value, isNull);
      expect(notifier.state.isError, isTrue);
      notifier.dispose();
    });
  });

  group('ArxaKitStateRecorder', () {
    test('kit.state.recorder — captures the emitted sequence with value equality', () async {
      final notifier = ArxaKitStateNotifier<int>();
      final recorder = ArxaKitStateRecorder<int>(notifier);
      notifier.emit(const ArxaKitLoading<int>());
      notifier.emit(const ArxaKitSuccess<int>(7));
      await Future<void>.delayed(Duration.zero);
      expect(recorder.states, const [
        ArxaKitIdle<int>(),
        ArxaKitLoading<int>(),
        ArxaKitSuccess<int>(7),
      ]);
      await recorder.dispose();
      notifier.dispose();
    });
  });

  group('ArxaKitRetryPolicy', () {
    test('kit.state.retry — delay curve grows by backoff and caps at maxDelay', () {
      const policy = ArxaKitRetryPolicy(
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
