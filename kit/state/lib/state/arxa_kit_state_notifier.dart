import 'dart:async';

import 'package:meta/meta.dart';

import 'arxa_kit_failure.dart';
import 'arxa_kit_state.dart';
import 'arxa_kit_state_transition.dart';

/// Holds the current [ArxaKitState] and broadcasts changes.
///
/// Pure Dart: a stored current value plus a broadcast [Stream]. Transitions are
/// checked against [ArxaKitStateTransition]; a transition outside the legal matrix
/// trips an assertion in debug (when [guardTransitions] is true) but is always
/// applied so release builds never crash on an unexpected sequence. Set
/// [guardTransitions] to false to disable the check entirely — the scriptable
/// test doubles in `arxa_kit_testing.dart` do this to push arbitrary sequences.
class ArxaKitStateNotifier<T> {
  ArxaKitStateNotifier({
    ArxaKitState<T>? initial,
    this.guardTransitions = true,
  }) : _state = initial ?? ArxaKitIdle<T>();

  ArxaKitState<T> _state;
  final StreamController<ArxaKitState<T>> _controller =
      StreamController<ArxaKitState<T>>.broadcast();

  /// When true (default), transitions outside [ArxaKitStateTransition] trip an
  /// assertion in debug builds.
  final bool guardTransitions;

  bool _disposed = false;

  /// The current state.
  ArxaKitState<T> get state => _state;

  /// Broadcast stream of state changes. Does not replay the current value —
  /// read [state] for that.
  Stream<ArxaKitState<T>> get stream => _controller.stream;

  bool get isDisposed => _disposed;

  /// Emits [next], updating [state] and notifying listeners.
  ///
  /// No-ops when [next] equals the current state. Flags illegal transitions in
  /// debug when [guardTransitions] is true.
  void emit(ArxaKitState<T> next) {
    if (_disposed) {
      throw StateError('emit called on a disposed ArxaKitStateNotifier');
    }
    if (next == _state) return;
    assert(
      !guardTransitions || ArxaKitStateTransition.isLegal(_state, next),
      'Illegal ArxaKitState transition: '
      '${_state.runtimeType} -> ${next.runtimeType}',
    );
    _setState(next);
  }

  /// Applies [next] without the transition check or equality no-op. Intended
  /// for subclasses (e.g. scriptable test doubles) that need to push arbitrary
  /// sequences.
  @protected
  void setStateUnguarded(ArxaKitState<T> next) {
    if (_disposed) {
      throw StateError('setStateUnguarded called on a disposed '
          'ArxaKitStateNotifier');
    }
    _setState(next);
  }

  void _setState(ArxaKitState<T> next) {
    _state = next;
    _controller.add(next);
  }

  /// Runs [future], driving the state loading → success/error.
  ///
  /// Emits [ArxaKitLoading] immediately, then [ArxaKitSuccess] with the resolved value
  /// or [ArxaKitError] wrapping any thrown error via [ArxaKitFailure.from]. Returns the
  /// value on success, or null on error (unless [rethrowError] is true, in
  /// which case the error is rethrown after the [ArxaKitError] emission).
  Future<T?> track(
    Future<T> future, {
    bool rethrowError = false,
  }) async {
    emit(ArxaKitState<T>.loading());
    try {
      final value = await future;
      emit(ArxaKitState<T>.success(value));
      return value;
    } catch (error, stackTrace) {
      emit(ArxaKitState<T>.error(ArxaKitFailure.from(error, stackTrace)));
      if (rethrowError) rethrow;
      return null;
    }
  }

  /// Resets the notifier back to [ArxaKitIdle].
  void reset() => emit(ArxaKitIdle<T>());

  /// Closes the underlying stream. The notifier must not be used afterwards.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller.close();
  }
}
