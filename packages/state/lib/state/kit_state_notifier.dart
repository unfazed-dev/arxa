import 'dart:async';

import 'package:meta/meta.dart';

import 'kit_failure.dart';
import 'kit_state.dart';
import 'kit_state_transition.dart';

/// Holds the current [KitState] and broadcasts changes.
///
/// Pure Dart: a stored current value plus a broadcast [Stream]. Transitions are
/// checked against [KitStateTransition]; a transition outside the legal matrix
/// trips an assertion in debug (when [guardTransitions] is true) but is always
/// applied so release builds never crash on an unexpected sequence. Set
/// [guardTransitions] to false to disable the check entirely — the scriptable
/// test doubles in `testing.dart` do this to push arbitrary sequences.
class KitStateNotifier<T> {
  KitStateNotifier({
    KitState<T>? initial,
    this.guardTransitions = true,
  }) : _state = initial ?? KitIdle<T>();

  KitState<T> _state;
  final StreamController<KitState<T>> _controller =
      StreamController<KitState<T>>.broadcast();

  /// When true (default), transitions outside [KitStateTransition] trip an
  /// assertion in debug builds.
  final bool guardTransitions;

  bool _disposed = false;

  /// The current state.
  KitState<T> get state => _state;

  /// Broadcast stream of state changes. Does not replay the current value —
  /// read [state] for that.
  Stream<KitState<T>> get stream => _controller.stream;

  bool get isDisposed => _disposed;

  /// Emits [next], updating [state] and notifying listeners.
  ///
  /// No-ops when [next] equals the current state. Flags illegal transitions in
  /// debug when [guardTransitions] is true.
  void emit(KitState<T> next) {
    if (_disposed) {
      throw StateError('emit called on a disposed KitStateNotifier');
    }
    if (next == _state) return;
    assert(
      !guardTransitions || KitStateTransition.isLegal(_state, next),
      'Illegal KitState transition: '
      '${_state.runtimeType} -> ${next.runtimeType}',
    );
    _setState(next);
  }

  /// Applies [next] without the transition check or equality no-op. Intended
  /// for subclasses (e.g. scriptable test doubles) that need to push arbitrary
  /// sequences.
  @protected
  void setStateUnguarded(KitState<T> next) {
    if (_disposed) {
      throw StateError('setStateUnguarded called on a disposed '
          'KitStateNotifier');
    }
    _setState(next);
  }

  void _setState(KitState<T> next) {
    _state = next;
    _controller.add(next);
  }

  /// Runs [future], driving the state loading → success/error.
  ///
  /// Emits [KitLoading] immediately, then [KitSuccess] with the resolved value
  /// or [KitError] wrapping any thrown error via [KitFailure.from]. Returns the
  /// value on success, or null on error (unless [rethrowError] is true, in
  /// which case the error is rethrown after the [KitError] emission).
  Future<T?> track(
    Future<T> future, {
    bool rethrowError = false,
  }) async {
    emit(KitState<T>.loading());
    try {
      final value = await future;
      emit(KitState<T>.success(value));
      return value;
    } catch (error, stackTrace) {
      emit(KitState<T>.error(KitFailure.from(error, stackTrace)));
      if (rethrowError) rethrow;
      return null;
    }
  }

  /// Resets the notifier back to [KitIdle].
  void reset() => emit(KitIdle<T>());

  /// Closes the underlying stream. The notifier must not be used afterwards.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller.close();
  }
}
