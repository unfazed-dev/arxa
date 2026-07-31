import 'package:meta/meta.dart';

import 'kit_failure.dart';

/// A sealed, immutable state vocabulary for an asynchronous value of type [T].
///
/// Five cases: [KitIdle], [KitPending], [KitLoading], [KitSuccess],
/// [KitError]. Use pattern matching (`switch`) directly, or the [when] / [map]
/// combinators. Every case implements value equality, so sequences of states
/// can be compared directly in tests.
@immutable
sealed class KitState<T> {
  const KitState();

  const factory KitState.idle() = KitIdle<T>;
  const factory KitState.pending() = KitPending<T>;
  const factory KitState.loading([double? progress]) = KitLoading<T>;
  const factory KitState.success(T data) = KitSuccess<T>;
  const factory KitState.error(KitFailure failure) = KitError<T>;

  /// Exhaustive fold over the *payloads* of each case.
  R when<R>({
    required R Function() idle,
    required R Function() pending,
    required R Function(double? progress) loading,
    required R Function(T data) success,
    required R Function(KitFailure failure) error,
  }) {
    final self = this;
    return switch (self) {
      KitIdle<T>() => idle(),
      KitPending<T>() => pending(),
      KitLoading<T>() => loading(self.progress),
      KitSuccess<T>() => success(self.data),
      KitError<T>() => error(self.failure),
    };
  }

  /// Non-exhaustive fold over payloads: supply the cases you care about and an
  /// [orElse] for the rest.
  R maybeWhen<R>({
    R Function()? idle,
    R Function()? pending,
    R Function(double? progress)? loading,
    R Function(T data)? success,
    R Function(KitFailure failure)? error,
    required R Function() orElse,
  }) {
    final self = this;
    return switch (self) {
      KitIdle<T>() => idle?.call() ?? orElse(),
      KitPending<T>() => pending?.call() ?? orElse(),
      KitLoading<T>() => loading?.call(self.progress) ?? orElse(),
      KitSuccess<T>() => success?.call(self.data) ?? orElse(),
      KitError<T>() => error?.call(self.failure) ?? orElse(),
    };
  }

  /// Exhaustive fold over the *case objects* themselves.
  R map<R>({
    required R Function(KitIdle<T> state) idle,
    required R Function(KitPending<T> state) pending,
    required R Function(KitLoading<T> state) loading,
    required R Function(KitSuccess<T> state) success,
    required R Function(KitError<T> state) error,
  }) {
    final self = this;
    return switch (self) {
      KitIdle<T>() => idle(self),
      KitPending<T>() => pending(self),
      KitLoading<T>() => loading(self),
      KitSuccess<T>() => success(self),
      KitError<T>() => error(self),
    };
  }

  /// Non-exhaustive fold over case objects, with an [orElse] fallback.
  R maybeMap<R>({
    R Function(KitIdle<T> state)? idle,
    R Function(KitPending<T> state)? pending,
    R Function(KitLoading<T> state)? loading,
    R Function(KitSuccess<T> state)? success,
    R Function(KitError<T> state)? error,
    required R Function() orElse,
  }) {
    final self = this;
    return switch (self) {
      KitIdle<T>() => idle?.call(self) ?? orElse(),
      KitPending<T>() => pending?.call(self) ?? orElse(),
      KitLoading<T>() => loading?.call(self) ?? orElse(),
      KitSuccess<T>() => success?.call(self) ?? orElse(),
      KitError<T>() => error?.call(self) ?? orElse(),
    };
  }

  bool get isIdle => this is KitIdle<T>;
  bool get isPending => this is KitPending<T>;
  bool get isLoading => this is KitLoading<T>;
  bool get isSuccess => this is KitSuccess<T>;
  bool get isError => this is KitError<T>;

  /// True while the state represents in-flight work ([KitPending] or
  /// [KitLoading]).
  bool get isBusy => this is KitPending<T> || this is KitLoading<T>;

  /// The success value, or null for any other case.
  T? get dataOrNull => this is KitSuccess<T> ? (this as KitSuccess<T>).data : null;

  /// The failure, or null for any other case.
  KitFailure? get failureOrNull =>
      this is KitError<T> ? (this as KitError<T>).failure : null;
}

/// The initial, no-work-requested state.
@immutable
final class KitIdle<T> extends KitState<T> {
  const KitIdle();

  @override
  bool operator ==(Object other) =>
      other is KitIdle<T> && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'KitIdle<$T>()';
}

/// Work has been requested but not yet started (e.g. debounce/queue window).
@immutable
final class KitPending<T> extends KitState<T> {
  const KitPending();

  @override
  bool operator ==(Object other) =>
      other is KitPending<T> && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'KitPending<$T>()';
}

/// Work is in flight, optionally with a [progress] value in `[0, 1]`.
@immutable
final class KitLoading<T> extends KitState<T> {
  const KitLoading([this.progress]);

  /// Progress in `[0, 1]`, or null when indeterminate.
  final double? progress;

  @override
  bool operator ==(Object other) =>
      other is KitLoading<T> &&
      runtimeType == other.runtimeType &&
      progress == other.progress;

  @override
  int get hashCode => Object.hash(runtimeType, progress);

  @override
  String toString() => 'KitLoading<$T>(progress: $progress)';
}

/// Work completed successfully with [data].
@immutable
final class KitSuccess<T> extends KitState<T> {
  const KitSuccess(this.data);

  final T data;

  @override
  bool operator ==(Object other) =>
      other is KitSuccess<T> &&
      runtimeType == other.runtimeType &&
      data == other.data;

  @override
  int get hashCode => Object.hash(runtimeType, data);

  @override
  String toString() => 'KitSuccess<$T>($data)';
}

/// Work failed with [failure].
@immutable
final class KitError<T> extends KitState<T> {
  const KitError(this.failure);

  final KitFailure failure;

  @override
  bool operator ==(Object other) =>
      other is KitError<T> &&
      runtimeType == other.runtimeType &&
      failure == other.failure;

  @override
  int get hashCode => Object.hash(runtimeType, failure);

  @override
  String toString() => 'KitError<$T>($failure)';
}
