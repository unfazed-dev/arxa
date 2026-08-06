import 'dart:async';

import 'package:meta/meta.dart';

import 'appbox_kit_failure.dart';
import 'appbox_kit_state.dart';
import 'appbox_kit_state_transition.dart';

/// Holds the current [AppBoxKitState] and broadcasts changes.
///
/// Pure Dart: a stored current value plus a broadcast [Stream]. Transitions are
/// checked against [AppBoxKitStateTransition]; a transition outside the legal matrix
/// trips an assertion in debug (when [guardTransitions] is true) but is always
/// applied so release builds never crash on an unexpected sequence. Set
/// [guardTransitions] to false to disable the check entirely — the scriptable
/// test doubles in `appbox_kit_testing.dart` do this to push arbitrary sequences.
class AppBoxKitStateNotifier<T> {
  AppBoxKitStateNotifier({
    AppBoxKitState<T>? initial,
    this.guardTransitions = true,
  }) : _state = initial ?? AppBoxKitIdle<T>();

  AppBoxKitState<T> _state;
  final StreamController<AppBoxKitState<T>> _controller =
      StreamController<AppBoxKitState<T>>.broadcast();

  /// When true (default), transitions outside [AppBoxKitStateTransition] trip an
  /// assertion in debug builds.
  final bool guardTransitions;

  bool _disposed = false;

  /// The current state.
  AppBoxKitState<T> get state => _state;

  /// Broadcast stream of state changes. Does not replay the current value —
  /// read [state] for that.
  Stream<AppBoxKitState<T>> get stream => _controller.stream;

  bool get isDisposed => _disposed;

  /// Emits [next], updating [state] and notifying listeners.
  ///
  /// No-ops when [next] equals the current state. Flags illegal transitions in
  /// debug when [guardTransitions] is true.
  void emit(AppBoxKitState<T> next) {
    if (_disposed) {
      throw StateError('emit called on a disposed AppBoxKitStateNotifier');
    }
    if (next == _state) return;
    assert(
      !guardTransitions || AppBoxKitStateTransition.isLegal(_state, next),
      'Illegal AppBoxKitState transition: '
      '${_state.runtimeType} -> ${next.runtimeType}',
    );
    _setState(next);
  }

  /// Applies [next] without the transition check or equality no-op. Intended
  /// for subclasses (e.g. scriptable test doubles) that need to push arbitrary
  /// sequences.
  @protected
  void setStateUnguarded(AppBoxKitState<T> next) {
    if (_disposed) {
      throw StateError('setStateUnguarded called on a disposed '
          'AppBoxKitStateNotifier');
    }
    _setState(next);
  }

  void _setState(AppBoxKitState<T> next) {
    _state = next;
    _controller.add(next);
  }

  /// Runs [future], driving the state loading → success/error.
  ///
  /// Emits [AppBoxKitLoading] immediately, then [AppBoxKitSuccess] with the resolved value
  /// or [AppBoxKitError] wrapping any thrown error via [AppBoxKitFailure.from]. Returns the
  /// value on success, or null on error (unless [rethrowError] is true, in
  /// which case the error is rethrown after the [AppBoxKitError] emission).
  Future<T?> track(
    Future<T> future, {
    bool rethrowError = false,
  }) async {
    emit(AppBoxKitState<T>.loading());
    try {
      final value = await future;
      emit(AppBoxKitState<T>.success(value));
      return value;
    } catch (error, stackTrace) {
      emit(AppBoxKitState<T>.error(AppBoxKitFailure.from(error, stackTrace)));
      if (rethrowError) rethrow;
      return null;
    }
  }

  /// Resets the notifier back to [AppBoxKitIdle].
  void reset() => emit(AppBoxKitIdle<T>());

  /// Closes the underlying stream. The notifier must not be used afterwards.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller.close();
  }
}
