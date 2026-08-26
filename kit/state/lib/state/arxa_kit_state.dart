import 'package:meta/meta.dart';

import 'arxa_kit_failure.dart';

/// A sealed, immutable state vocabulary for an asynchronous value of type [T].
///
/// Five cases: [ArxaKitIdle], [ArxaKitPending], [ArxaKitLoading], [ArxaKitSuccess],
/// [ArxaKitError]. Use pattern matching (`switch`) directly, or the [when] / [map]
/// combinators. Every case implements value equality, so sequences of states
/// can be compared directly in tests.
@immutable
sealed class ArxaKitState<T> {
  const ArxaKitState();

  const factory ArxaKitState.idle() = ArxaKitIdle<T>;
  const factory ArxaKitState.pending() = ArxaKitPending<T>;
  const factory ArxaKitState.loading([double? progress]) = ArxaKitLoading<T>;
  const factory ArxaKitState.success(T data) = ArxaKitSuccess<T>;
  const factory ArxaKitState.error(ArxaKitFailure failure) = ArxaKitError<T>;

  /// Exhaustive fold over the *payloads* of each case.
  R when<R>({
    required R Function() idle,
    required R Function() pending,
    required R Function(double? progress) loading,
    required R Function(T data) success,
    required R Function(ArxaKitFailure failure) error,
  }) {
    final self = this;
    return switch (self) {
      ArxaKitIdle<T>() => idle(),
      ArxaKitPending<T>() => pending(),
      ArxaKitLoading<T>() => loading(self.progress),
      ArxaKitSuccess<T>() => success(self.data),
      ArxaKitError<T>() => error(self.failure),
    };
  }

  /// Non-exhaustive fold over payloads: supply the cases you care about and an
  /// [orElse] for the rest.
  R maybeWhen<R>({
    R Function()? idle,
    R Function()? pending,
    R Function(double? progress)? loading,
    R Function(T data)? success,
    R Function(ArxaKitFailure failure)? error,
    required R Function() orElse,
  }) {
    final self = this;
    return switch (self) {
      ArxaKitIdle<T>() => idle?.call() ?? orElse(),
      ArxaKitPending<T>() => pending?.call() ?? orElse(),
      ArxaKitLoading<T>() => loading?.call(self.progress) ?? orElse(),
      ArxaKitSuccess<T>() => success?.call(self.data) ?? orElse(),
      ArxaKitError<T>() => error?.call(self.failure) ?? orElse(),
    };
  }

  /// Exhaustive fold over the *case objects* themselves.
  R map<R>({
    required R Function(ArxaKitIdle<T> state) idle,
    required R Function(ArxaKitPending<T> state) pending,
    required R Function(ArxaKitLoading<T> state) loading,
    required R Function(ArxaKitSuccess<T> state) success,
    required R Function(ArxaKitError<T> state) error,
  }) {
    final self = this;
    return switch (self) {
      ArxaKitIdle<T>() => idle(self),
      ArxaKitPending<T>() => pending(self),
      ArxaKitLoading<T>() => loading(self),
      ArxaKitSuccess<T>() => success(self),
      ArxaKitError<T>() => error(self),
    };
  }

  /// Non-exhaustive fold over case objects, with an [orElse] fallback.
  R maybeMap<R>({
    R Function(ArxaKitIdle<T> state)? idle,
    R Function(ArxaKitPending<T> state)? pending,
    R Function(ArxaKitLoading<T> state)? loading,
    R Function(ArxaKitSuccess<T> state)? success,
    R Function(ArxaKitError<T> state)? error,
    required R Function() orElse,
  }) {
    final self = this;
    return switch (self) {
      ArxaKitIdle<T>() => idle?.call(self) ?? orElse(),
      ArxaKitPending<T>() => pending?.call(self) ?? orElse(),
      ArxaKitLoading<T>() => loading?.call(self) ?? orElse(),
      ArxaKitSuccess<T>() => success?.call(self) ?? orElse(),
      ArxaKitError<T>() => error?.call(self) ?? orElse(),
    };
  }

  bool get isIdle => this is ArxaKitIdle<T>;
  bool get isPending => this is ArxaKitPending<T>;
  bool get isLoading => this is ArxaKitLoading<T>;
  bool get isSuccess => this is ArxaKitSuccess<T>;
  bool get isError => this is ArxaKitError<T>;

  /// True while the state represents in-flight work ([ArxaKitPending] or
  /// [ArxaKitLoading]).
  bool get isBusy => this is ArxaKitPending<T> || this is ArxaKitLoading<T>;

  /// The success value, or null for any other case.
  T? get dataOrNull => this is ArxaKitSuccess<T> ? (this as ArxaKitSuccess<T>).data : null;

  /// The failure, or null for any other case.
  ArxaKitFailure? get failureOrNull =>
      this is ArxaKitError<T> ? (this as ArxaKitError<T>).failure : null;
}

/// The initial, no-work-requested state.
@immutable
final class ArxaKitIdle<T> extends ArxaKitState<T> {
  const ArxaKitIdle();

  @override
  bool operator ==(Object other) =>
      other is ArxaKitIdle<T> && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'ArxaKitIdle<$T>()';
}

/// Work has been requested but not yet started (e.g. debounce/queue window).
@immutable
final class ArxaKitPending<T> extends ArxaKitState<T> {
  const ArxaKitPending();

  @override
  bool operator ==(Object other) =>
      other is ArxaKitPending<T> && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'ArxaKitPending<$T>()';
}

/// Work is in flight, optionally with a [progress] value in `[0, 1]`.
@immutable
final class ArxaKitLoading<T> extends ArxaKitState<T> {
  const ArxaKitLoading([this.progress]);

  /// Progress in `[0, 1]`, or null when indeterminate.
  final double? progress;

  @override
  bool operator ==(Object other) =>
      other is ArxaKitLoading<T> &&
      runtimeType == other.runtimeType &&
      progress == other.progress;

  @override
  int get hashCode => Object.hash(runtimeType, progress);

  @override
  String toString() => 'ArxaKitLoading<$T>(progress: $progress)';
}

/// Work completed successfully with [data].
@immutable
final class ArxaKitSuccess<T> extends ArxaKitState<T> {
  const ArxaKitSuccess(this.data);

  final T data;

  @override
  bool operator ==(Object other) =>
      other is ArxaKitSuccess<T> &&
      runtimeType == other.runtimeType &&
      data == other.data;

  @override
  int get hashCode => Object.hash(runtimeType, data);

  @override
  String toString() => 'ArxaKitSuccess<$T>($data)';
}

/// Work failed with [failure].
@immutable
final class ArxaKitError<T> extends ArxaKitState<T> {
  const ArxaKitError(this.failure);

  final ArxaKitFailure failure;

  @override
  bool operator ==(Object other) =>
      other is ArxaKitError<T> &&
      runtimeType == other.runtimeType &&
      failure == other.failure;

  @override
  int get hashCode => Object.hash(runtimeType, failure);

  @override
  String toString() => 'ArxaKitError<$T>($failure)';
}
