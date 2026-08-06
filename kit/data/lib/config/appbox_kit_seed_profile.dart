/// Seed Profile machinery for the Seed Backend: the named configuration a
/// host selects to force Read States deterministically (host vocabulary:
/// normal / empty / slow / failing / per-role users). The kit owns the two
/// behavioral levers — latency injection and failure injection — applied by
/// every `AppBoxKitSeedRepository` operation; the host owns the profile names,
/// the fixture selection (`empty` is an empty fixture list, not a store
/// behavior), and any persona sign-in after boot.
///
/// Only meaningful when `AppBoxKitDataConfig.backend` is `AppBoxKitDataBackend.seed` —
/// the other backends talk to real storage and never consult this.
library;

/// The typed error the `failing` profile raises. A distinct type (not a
/// generic [StateError]) so hosts and tests can assert the failure came
/// from the Seed Profile, not from a real bug in the data layer.
class AppBoxKitSeedException implements Exception {
  final String message;
  final String code;

  const AppBoxKitSeedException(
    this.message, {
    this.code = 'seed-profile-failure',
  });

  @override
  String toString() => 'AppBoxKitSeedException($code): $message';
}

/// Latency + failure injection for one Seed Backend boot.
///
/// - [latency] delays every repository operation and every emission of a
///   watched table (first emission included — that delay is what renders
///   the loading / Refreshing Read States).
/// - [error], when non-null, fails every repository operation and turns
///   every watch emission into a stream error (what renders the in-surface
///   error-with-retry Read State).
///
/// The default (`const AppBoxKitSeedProfile()`) is a pass-through: zero latency,
/// no failure — existing boots are behavior-identical without it. Auth is
/// never affected: `AppBoxKitSeedAuthService` reads the store directly, not
/// through repositories.
class AppBoxKitSeedProfile {
  /// Delay applied to every repository operation and watch emission.
  final Duration latency;

  /// When non-null, every repository operation throws / emits this error.
  final Object? error;

  /// The `normal` profile — no injection.
  const AppBoxKitSeedProfile({
    this.latency = Duration.zero,
    this.error,
  });

  /// The `slow` profile — everything succeeds, [latency] late.
  const AppBoxKitSeedProfile.slow(this.latency) : error = null;

  /// The `failing` profile — everything fails with [error].
  const AppBoxKitSeedProfile.failing(this.error) : latency = Duration.zero;

  /// Gates one one-shot operation: awaits [latency], then throws [error]
  /// when set. Repositories await this before touching the store.
  Future<void> gate() async {
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    final e = error;
    if (e != null) throw e;
  }

  /// Applies the profile to a watched table stream: [latency] delays every
  /// emission (asyncMap serializes, so bursts queue instead of
  /// interleaving), then [error] converts each emission into a stream
  /// error. The pass-through profile returns [source] untouched, so the
  /// stream keeps its exact runtime type for downstream `is` checks.
  Stream<T> apply<T>(Stream<T> source) {
    var result = source;
    if (latency > Duration.zero) {
      result = result.asyncMap(
        (value) => Future<T>.delayed(latency, () => value),
      );
    }
    final e = error;
    if (e != null) {
      result = result.asyncMap((_) => Future<T>.error(e));
    }
    return result;
  }
}
