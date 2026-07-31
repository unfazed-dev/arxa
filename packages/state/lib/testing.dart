/// Test doubles and recorders for appbox_kit_state.
///
/// Import in tests: `import 'package:appbox_kit_state/testing.dart';`
library;

import 'dart:async';

import 'appbox_kit_state.dart';

/// Records the sequence of states emitted by a [KitStateNotifier] for assertion
/// in tests.
///
/// Captures the notifier's current state at subscription time (unless
/// [recordInitial] is false), then every subsequent emission. Because
/// [KitState] implements value equality, the recorded list can be compared
/// directly with `expect(recorder.states, [...])`.
///
/// Emissions arrive on a broadcast stream (asynchronously), so drain the event
/// queue — e.g. `await Future<void>.delayed(Duration.zero)` — before asserting.
class KitStateRecorder<T> {
  KitStateRecorder(this._notifier, {bool recordInitial = true}) {
    if (recordInitial) _states.add(_notifier.state);
    _subscription = _notifier.stream.listen(_states.add);
  }

  final KitStateNotifier<T> _notifier;
  late final StreamSubscription<KitState<T>> _subscription;
  final List<KitState<T>> _states = <KitState<T>>[];

  /// All recorded states, in order.
  List<KitState<T>> get states => List.unmodifiable(_states);

  /// The most recently recorded state.
  KitState<T> get last => _states.last;

  /// The number of recorded states.
  int get length => _states.length;

  /// Clears the recorded history while keeping the subscription live.
  void clear() => _states.clear();

  /// Stops recording.
  Future<void> dispose() => _subscription.cancel();
}

/// A [KitStateNotifier] whose emissions are fully scripted and *bypass* the
/// transition guard, so tests can push illegal or arbitrary sequences (and even
/// repeat the same state).
class KitScriptedStateNotifier<T> extends KitStateNotifier<T> {
  KitScriptedStateNotifier([KitState<T>? initial])
      : super(initial: initial, guardTransitions: false);

  /// Pushes [next] unconditionally — no transition check, no equality no-op.
  void script(KitState<T> next) => setStateUnguarded(next);

  /// Pushes each state in [sequence] in order.
  void scriptAll(Iterable<KitState<T>> sequence) => sequence.forEach(script);
}
