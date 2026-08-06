import 'package:meta/meta.dart';

import 'appbox_kit_failure.dart';

/// A sealed, immutable state vocabulary for an asynchronous value of type [T].
///
/// Five cases: [AppBoxKitIdle], [AppBoxKitPending], [AppBoxKitLoading], [AppBoxKitSuccess],
/// [AppBoxKitError]. Use pattern matching (`switch`) directly, or the [when] / [map]
/// combinators. Every case implements value equality, so sequences of states
/// can be compared directly in tests.
@immutable
sealed class AppBoxKitState<T> {
  const AppBoxKitState();

  const factory AppBoxKitState.idle() = AppBoxKitIdle<T>;
  const factory AppBoxKitState.pending() = AppBoxKitPending<T>;
  const factory AppBoxKitState.loading([double? progress]) = AppBoxKitLoading<T>;
  const factory AppBoxKitState.success(T data) = AppBoxKitSuccess<T>;
  const factory AppBoxKitState.error(AppBoxKitFailure failure) = AppBoxKitError<T>;

  /// Exhaustive fold over the *payloads* of each case.
  R when<R>({
    required R Function() idle,
    required R Function() pending,
    required R Function(double? progress) loading,
    required R Function(T data) success,
    required R Function(AppBoxKitFailure failure) error,
  }) {
    final self = this;
    return switch (self) {
      AppBoxKitIdle<T>() => idle(),
      AppBoxKitPending<T>() => pending(),
      AppBoxKitLoading<T>() => loading(self.progress),
      AppBoxKitSuccess<T>() => success(self.data),
      AppBoxKitError<T>() => error(self.failure),
    };
  }

  /// Non-exhaustive fold over payloads: supply the cases you care about and an
  /// [orElse] for the rest.
  R maybeWhen<R>({
    R Function()? idle,
    R Function()? pending,
    R Function(double? progress)? loading,
    R Function(T data)? success,
    R Function(AppBoxKitFailure failure)? error,
    required R Function() orElse,
  }) {
    final self = this;
    return switch (self) {
      AppBoxKitIdle<T>() => idle?.call() ?? orElse(),
      AppBoxKitPending<T>() => pending?.call() ?? orElse(),
      AppBoxKitLoading<T>() => loading?.call(self.progress) ?? orElse(),
      AppBoxKitSuccess<T>() => success?.call(self.data) ?? orElse(),
      AppBoxKitError<T>() => error?.call(self.failure) ?? orElse(),
    };
  }

  /// Exhaustive fold over the *case objects* themselves.
  R map<R>({
    required R Function(AppBoxKitIdle<T> state) idle,
    required R Function(AppBoxKitPending<T> state) pending,
    required R Function(AppBoxKitLoading<T> state) loading,
    required R Function(AppBoxKitSuccess<T> state) success,
    required R Function(AppBoxKitError<T> state) error,
  }) {
    final self = this;
    return switch (self) {
      AppBoxKitIdle<T>() => idle(self),
      AppBoxKitPending<T>() => pending(self),
      AppBoxKitLoading<T>() => loading(self),
      AppBoxKitSuccess<T>() => success(self),
      AppBoxKitError<T>() => error(self),
    };
  }

  /// Non-exhaustive fold over case objects, with an [orElse] fallback.
  R maybeMap<R>({
    R Function(AppBoxKitIdle<T> state)? idle,
    R Function(AppBoxKitPending<T> state)? pending,
    R Function(AppBoxKitLoading<T> state)? loading,
    R Function(AppBoxKitSuccess<T> state)? success,
    R Function(AppBoxKitError<T> state)? error,
    required R Function() orElse,
  }) {
    final self = this;
    return switch (self) {
      AppBoxKitIdle<T>() => idle?.call(self) ?? orElse(),
      AppBoxKitPending<T>() => pending?.call(self) ?? orElse(),
      AppBoxKitLoading<T>() => loading?.call(self) ?? orElse(),
      AppBoxKitSuccess<T>() => success?.call(self) ?? orElse(),
      AppBoxKitError<T>() => error?.call(self) ?? orElse(),
    };
  }

  bool get isIdle => this is AppBoxKitIdle<T>;
  bool get isPending => this is AppBoxKitPending<T>;
  bool get isLoading => this is AppBoxKitLoading<T>;
  bool get isSuccess => this is AppBoxKitSuccess<T>;
  bool get isError => this is AppBoxKitError<T>;

  /// True while the state represents in-flight work ([AppBoxKitPending] or
  /// [AppBoxKitLoading]).
  bool get isBusy => this is AppBoxKitPending<T> || this is AppBoxKitLoading<T>;

  /// The success value, or null for any other case.
  T? get dataOrNull => this is AppBoxKitSuccess<T> ? (this as AppBoxKitSuccess<T>).data : null;

  /// The failure, or null for any other case.
  AppBoxKitFailure? get failureOrNull =>
      this is AppBoxKitError<T> ? (this as AppBoxKitError<T>).failure : null;
}

/// The initial, no-work-requested state.
@immutable
final class AppBoxKitIdle<T> extends AppBoxKitState<T> {
  const AppBoxKitIdle();

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitIdle<T> && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'AppBoxKitIdle<$T>()';
}

/// Work has been requested but not yet started (e.g. debounce/queue window).
@immutable
final class AppBoxKitPending<T> extends AppBoxKitState<T> {
  const AppBoxKitPending();

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitPending<T> && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'AppBoxKitPending<$T>()';
}

/// Work is in flight, optionally with a [progress] value in `[0, 1]`.
@immutable
final class AppBoxKitLoading<T> extends AppBoxKitState<T> {
  const AppBoxKitLoading([this.progress]);

  /// Progress in `[0, 1]`, or null when indeterminate.
  final double? progress;

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitLoading<T> &&
      runtimeType == other.runtimeType &&
      progress == other.progress;

  @override
  int get hashCode => Object.hash(runtimeType, progress);

  @override
  String toString() => 'AppBoxKitLoading<$T>(progress: $progress)';
}

/// Work completed successfully with [data].
@immutable
final class AppBoxKitSuccess<T> extends AppBoxKitState<T> {
  const AppBoxKitSuccess(this.data);

  final T data;

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitSuccess<T> &&
      runtimeType == other.runtimeType &&
      data == other.data;

  @override
  int get hashCode => Object.hash(runtimeType, data);

  @override
  String toString() => 'AppBoxKitSuccess<$T>($data)';
}

/// Work failed with [failure].
@immutable
final class AppBoxKitError<T> extends AppBoxKitState<T> {
  const AppBoxKitError(this.failure);

  final AppBoxKitFailure failure;

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitError<T> &&
      runtimeType == other.runtimeType &&
      failure == other.failure;

  @override
  int get hashCode => Object.hash(runtimeType, failure);

  @override
  String toString() => 'AppBoxKitError<$T>($failure)';
}
