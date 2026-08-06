import 'dart:async';

// ═══════════════════════════════════════════════════════════════════════════════
// KitAction v2.0 - Type Definitions
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 5.3: Result Types (lines 1302-1330)
//
// Defines cancellable operations, cancel tokens, and exception types.
// ═══════════════════════════════════════════════════════════════════════════════

/// Exception thrown when an operation is cancelled
class CancelledException implements Exception {
  final String message;

  CancelledException([this.message = 'Operation was cancelled']);

  @override
  String toString() => 'CancelledException: $message';
}

/// Exception thrown when an operation is throttled
class ThrottledException implements Exception {
  final String message;

  ThrottledException([this.message = 'Operation was throttled']);

  @override
  String toString() => 'ThrottledException: $message';
}

/// Exception thrown when an overlapping call is dropped by the re-entry guard
///
/// KitAction guards every execution against parallel runs of the same
/// widgetId (the Flutter Command / command_it convention). The dropped call
/// completes with the fallback when one was set via `completeOnError`,
/// otherwise it throws this exception. Opt out per chain with
/// `KitActionBuilder.withParallelExecution()`.
class GuardedException implements Exception {
  final String message;

  GuardedException([this.message = 'Operation is already running']);

  @override
  String toString() => 'GuardedException: $message';
}

/// Internal token used to track and cancel operations
class CancelToken {
  bool _cancelled = false;

  /// Cancels the operation
  void cancel() => _cancelled = true;

  /// Whether the operation has been cancelled
  bool get isCancelled => _cancelled;
}

/// Represents a cancellable operation that can be cancelled mid-execution
class KitActionCancellable<T> {
  /// The future representing the operation result
  final Future<T> future;

  /// The cancel token used to cancel the operation
  final CancelToken _cancelToken;

  /// Creates a cancellable operation
  KitActionCancellable({
    required this.future,
    required CancelToken cancelToken,
  }) : _cancelToken = cancelToken;

  /// Cancels the operation
  void cancel() {
    _cancelToken.cancel();
  }

  /// Whether the operation has been cancelled
  bool get isCancelled => _cancelToken.isCancelled;

  /// Gets the result of the operation
  /// Throws [CancelledException] if the operation was cancelled
  Future<T> get result => future;
}
