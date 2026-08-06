import 'appbox_kit_state.dart';

/// The legal state-transition matrix for [AppBoxKitState] sequences.
///
/// Legality is keyed on the *case* of the state, not its payload. A transition
/// outside this matrix (for example `idle → success` without passing through a
/// busy state) is not illegal at runtime, but is *flagged in debug* by
/// `AppBoxKitStateNotifier` via an assertion.
///
/// Matrix (row → allowed successors):
/// - idle    → idle, pending, loading
/// - pending → pending, loading, success, error, idle
/// - loading → loading, success, error, idle
/// - success → loading, pending, idle
/// - error   → loading, pending, idle
abstract final class AppBoxKitStateTransition {
  static const Map<Type, Set<Type>> _matrix = {
    AppBoxKitIdle: {AppBoxKitIdle, AppBoxKitPending, AppBoxKitLoading},
    AppBoxKitPending: {AppBoxKitPending, AppBoxKitLoading, AppBoxKitSuccess, AppBoxKitError, AppBoxKitIdle},
    AppBoxKitLoading: {AppBoxKitLoading, AppBoxKitSuccess, AppBoxKitError, AppBoxKitIdle},
    AppBoxKitSuccess: {AppBoxKitLoading, AppBoxKitPending, AppBoxKitIdle},
    AppBoxKitError: {AppBoxKitLoading, AppBoxKitPending, AppBoxKitIdle},
  };

  /// Whether moving from [from] to [to] is within the legal matrix.
  static bool isLegal(AppBoxKitState<Object?> from, AppBoxKitState<Object?> to) {
    final allowed = _matrix[_caseOf(from)];
    return allowed != null && allowed.contains(_caseOf(to));
  }

  static Type _caseOf(AppBoxKitState<Object?> state) => switch (state) {
        AppBoxKitIdle() => AppBoxKitIdle,
        AppBoxKitPending() => AppBoxKitPending,
        AppBoxKitLoading() => AppBoxKitLoading,
        AppBoxKitSuccess() => AppBoxKitSuccess,
        AppBoxKitError() => AppBoxKitError,
      };
}
