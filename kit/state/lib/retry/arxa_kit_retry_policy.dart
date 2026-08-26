/// STUB (scheduled: retry-policy phase).
///
/// Describes how a failed tracked operation should be retried. The value object
/// and its delay curve are defined now (and unit-testable); wiring it into
/// `ArxaKitStateNotifier.track` (attempt accounting, jitter, cancellation) lands in
/// a later phase.
class ArxaKitRetryPolicy {
  const ArxaKitRetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 300),
    this.backoffFactor = 2.0,
    this.maxDelay = const Duration(seconds: 10),
  })  : assert(maxAttempts >= 1, 'maxAttempts must be >= 1'),
        assert(backoffFactor >= 1.0, 'backoffFactor must be >= 1.0');

  /// A policy that never retries (a single attempt).
  static const ArxaKitRetryPolicy none = ArxaKitRetryPolicy(maxAttempts: 1);

  /// Total attempts allowed, including the first (>= 1).
  final int maxAttempts;

  /// Delay before the *second* attempt; subsequent delays grow by
  /// [backoffFactor].
  final Duration initialDelay;

  /// Exponential backoff multiplier (>= 1.0).
  final double backoffFactor;

  /// Upper bound on any single delay.
  final Duration maxDelay;

  /// The delay before [attempt] (1-based). Attempt 1 has no delay.
  Duration delayForAttempt(int attempt) {
    if (attempt <= 1) return Duration.zero;
    final millis = initialDelay.inMilliseconds * _pow(backoffFactor, attempt - 2);
    final capped = millis.clamp(0, maxDelay.inMilliseconds.toDouble());
    return Duration(milliseconds: capped.round());
  }

  static double _pow(double base, int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= base;
    }
    return result;
  }
}
