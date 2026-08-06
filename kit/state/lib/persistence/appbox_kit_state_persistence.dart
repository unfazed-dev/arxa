import '../state/appbox_kit_state.dart';

/// STUB (scheduled: state-hydration phase).
///
/// Persists and restores the last *terminal* [AppBoxKitState] for a keyed flow, so a
/// screen can rehydrate its last success/error across app launches. The port
/// is defined now so hosts can code against the seam; the concrete
/// snapshot-backed implementation lands in a later phase.
abstract interface class AppBoxKitStatePersistence<T> {
  /// Persists [state] under [key]. Implementations typically store only
  /// terminal states (success/error) and ignore transient busy states.
  Future<void> save(String key, AppBoxKitState<T> state);

  /// Restores the last persisted state for [key], or null when none exists.
  Future<AppBoxKitState<T>?> restore(String key);

  /// Clears any persisted state for [key].
  Future<void> clear(String key);
}

/// STUB placeholder: a no-op [AppBoxKitStatePersistence] that persists nothing.
///
/// Lets hosts wire the seam today; swap for a durable store in the hydration
/// phase.
class AppBoxKitNoStatePersistence<T> implements AppBoxKitStatePersistence<T> {
  const AppBoxKitNoStatePersistence();

  @override
  Future<void> save(String key, AppBoxKitState<T> state) async {}

  @override
  Future<AppBoxKitState<T>?> restore(String key) async => null;

  @override
  Future<void> clear(String key) async {}
}
