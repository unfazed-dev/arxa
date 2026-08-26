import 'dart:async';

// ═══════════════════════════════════════════════════════════════════════════════
// ArxaKitAction v2.0 - Type Definitions
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 5.3: Result Types (lines 1302-1330)
//
// Defines cancellable operations, cancel tokens, and exception types.
// ═══════════════════════════════════════════════════════════════════════════════

/// Exception thrown when an operation is cancelled
class ArxaKitCancelledException implements Exception {
  final String message;

  ArxaKitCancelledException([this.message = 'Operation was cancelled']);

  @override
  String toString() => 'ArxaKitCancelledException: $message';
}

/// Exception thrown when an operation is throttled
class ArxaKitThrottledException implements Exception {
  final String message;

  ArxaKitThrottledException([this.message = 'Operation was throttled']);

  @override
  String toString() => 'ArxaKitThrottledException: $message';
}

/// Exception thrown when an overlapping call is dropped by the re-entry guard
///
/// ArxaKitAction guards every execution against parallel runs of the same
/// widgetId (the Flutter Command / command_it convention). The dropped call
/// completes with the fallback when one was set via `completeOnError`,
/// otherwise it throws this exception. Opt out per chain with
/// `ArxaKitActionBuilder.withParallelExecution()`.
class ArxaKitGuardedException implements Exception {
  final String message;

  ArxaKitGuardedException([this.message = 'Operation is already running']);

  @override
  String toString() => 'ArxaKitGuardedException: $message';
}

/// Internal token used to track and cancel operations
class ArxaKitCancelToken {
  bool _cancelled = false;

  /// Cancels the operation
  void cancel() => _cancelled = true;

  /// Whether the operation has been cancelled
  bool get isCancelled => _cancelled;
}

/// Represents a cancellable operation that can be cancelled mid-execution
class ArxaKitActionCancellable<T> {
  /// The future representing the operation result
  final Future<T> future;

  /// The cancel token used to cancel the operation
  final ArxaKitCancelToken _cancelToken;

  /// Creates a cancellable operation
  ArxaKitActionCancellable({
    required this.future,
    required ArxaKitCancelToken cancelToken,
  }) : _cancelToken = cancelToken;

  /// Cancels the operation
  void cancel() {
    _cancelToken.cancel();
  }

  /// Whether the operation has been cancelled
  bool get isCancelled => _cancelToken.isCancelled;

  /// Gets the result of the operation
  /// Throws [ArxaKitCancelledException] if the operation was cancelled
  Future<T> get result => future;
}
