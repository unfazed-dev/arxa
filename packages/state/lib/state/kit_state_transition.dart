import 'kit_state.dart';

/// The legal state-transition matrix for [KitState] sequences.
///
/// Legality is keyed on the *case* of the state, not its payload. A transition
/// outside this matrix (for example `idle → success` without passing through a
/// busy state) is not illegal at runtime, but is *flagged in debug* by
/// `KitStateNotifier` via an assertion.
///
/// Matrix (row → allowed successors):
/// - idle    → idle, pending, loading
/// - pending → pending, loading, success, error, idle
/// - loading → loading, success, error, idle
/// - success → loading, pending, idle
/// - error   → loading, pending, idle
abstract final class KitStateTransition {
  static const Map<Type, Set<Type>> _matrix = {
    KitIdle: {KitIdle, KitPending, KitLoading},
    KitPending: {KitPending, KitLoading, KitSuccess, KitError, KitIdle},
    KitLoading: {KitLoading, KitSuccess, KitError, KitIdle},
    KitSuccess: {KitLoading, KitPending, KitIdle},
    KitError: {KitLoading, KitPending, KitIdle},
  };

  /// Whether moving from [from] to [to] is within the legal matrix.
  static bool isLegal(KitState<Object?> from, KitState<Object?> to) {
    final allowed = _matrix[_caseOf(from)];
    return allowed != null && allowed.contains(_caseOf(to));
  }

  static Type _caseOf(KitState<Object?> state) => switch (state) {
        KitIdle() => KitIdle,
        KitPending() => KitPending,
        KitLoading() => KitLoading,
        KitSuccess() => KitSuccess,
        KitError() => KitError,
      };
}
