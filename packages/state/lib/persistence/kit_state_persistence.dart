import '../state/kit_state.dart';

/// STUB (scheduled: state-hydration phase).
///
/// Persists and restores the last *terminal* [KitState] for a keyed flow, so a
/// screen can rehydrate its last success/error across app launches. The port
/// is defined now so hosts can code against the seam; the concrete
/// snapshot-backed implementation lands in a later phase.
abstract interface class KitStatePersistence<T> {
  /// Persists [state] under [key]. Implementations typically store only
  /// terminal states (success/error) and ignore transient busy states.
  Future<void> save(String key, KitState<T> state);

  /// Restores the last persisted state for [key], or null when none exists.
  Future<KitState<T>?> restore(String key);

  /// Clears any persisted state for [key].
  Future<void> clear(String key);
}

/// STUB placeholder: a no-op [KitStatePersistence] that persists nothing.
///
/// Lets hosts wire the seam today; swap for a durable store in the hydration
/// phase.
class KitNoStatePersistence<T> implements KitStatePersistence<T> {
  const KitNoStatePersistence();

  @override
  Future<void> save(String key, KitState<T> state) async {}

  @override
  Future<KitState<T>?> restore(String key) async => null;

  @override
  Future<void> clear(String key) async {}
}
