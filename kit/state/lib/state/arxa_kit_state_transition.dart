import 'arxa_kit_state.dart';

/// The legal state-transition matrix for [ArxaKitState] sequences.
///
/// Legality is keyed on the *case* of the state, not its payload. A transition
/// outside this matrix (for example `idle → success` without passing through a
/// busy state) is not illegal at runtime, but is *flagged in debug* by
/// `ArxaKitStateNotifier` via an assertion.
///
/// Matrix (row → allowed successors):
/// - idle    → idle, pending, loading
/// - pending → pending, loading, success, error, idle
/// - loading → loading, success, error, idle
/// - success → loading, pending, idle
/// - error   → loading, pending, idle
abstract final class ArxaKitStateTransition {
  static const Map<Type, Set<Type>> _matrix = {
    ArxaKitIdle: {ArxaKitIdle, ArxaKitPending, ArxaKitLoading},
    ArxaKitPending: {ArxaKitPending, ArxaKitLoading, ArxaKitSuccess, ArxaKitError, ArxaKitIdle},
    ArxaKitLoading: {ArxaKitLoading, ArxaKitSuccess, ArxaKitError, ArxaKitIdle},
    ArxaKitSuccess: {ArxaKitLoading, ArxaKitPending, ArxaKitIdle},
    ArxaKitError: {ArxaKitLoading, ArxaKitPending, ArxaKitIdle},
  };

  /// Whether moving from [from] to [to] is within the legal matrix.
  static bool isLegal(ArxaKitState<Object?> from, ArxaKitState<Object?> to) {
    final allowed = _matrix[_caseOf(from)];
    return allowed != null && allowed.contains(_caseOf(to));
  }

  static Type _caseOf(ArxaKitState<Object?> state) => switch (state) {
        ArxaKitIdle() => ArxaKitIdle,
        ArxaKitPending() => ArxaKitPending,
        ArxaKitLoading() => ArxaKitLoading,
        ArxaKitSuccess() => ArxaKitSuccess,
        ArxaKitError() => ArxaKitError,
      };
}
