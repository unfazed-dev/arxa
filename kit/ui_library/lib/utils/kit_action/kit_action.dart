import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import 'kit_action_builder.dart';
import 'managers/stream_manager.dart';
import 'package:appbox_kit_core/kit_locator.dart';
import 'package:appbox_kit_core/services/error/kit_error_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// KitAction v2.0 - Main Facade
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 4.2: Component Responsibilities (Facade)
//    - Section 5.1: Main API Surface
//
// This class provides the main entry point for KitAction operations.
// See specification for complete API documentation and design principles.
// ═══════════════════════════════════════════════════════════════════════════════

/// Main entry point for KitAction - a fluent API for executing operations
///
/// KitAction provides automatic error handling, loading state management,
/// user notifications, and reactive stream support with a clean, chainable API.
///
/// **Basic Usage:**
/// ```dart
/// await KitAction.run<User>(
///   operation: () => fetchUser(id),
///   widgetId: 'profile',
/// )
///   .withLoading(setBusy)
///   .withErrorFallback('Failed to load user', fallback: User.empty())
///   .withSnackbars(success: 'User loaded', error: 'Load failed')
///   .execute();
/// ```
///
/// **With Retry:**
/// ```dart
/// await KitAction.run<String>(
///   operation: () => apiCall(),
///   widgetId: 'api',
/// )
///   .withRetry(maxAttempts: 3, delay: Duration(seconds: 1))
///   .withTimeout(Duration(seconds: 30))
///   .execute();
/// ```
///
/// **Reactive Streams:**
/// ```dart
/// final stream = KitAction.run<User>(
///   operation: () => fetchUser(id),
///   widgetId: 'profile',
/// )
///   .asStream(initialValue: User.empty())
///   .executeAsStream();
///
/// stream.listen((user) => print('User: ${user.name}'));
/// ```
///
/// **Cancellable Operations:**
/// ```dart
/// final cancellable = KitAction.run<String>(
///   operation: () async {
///     await Future.delayed(Duration(seconds: 5));
///     return 'result';
///   },
///   widgetId: 'long_operation',
/// )
///   .asCancellable()
///   .executeAsCancellable();
///
/// // Later...
/// cancellable.cancel();
/// ```
class KitAction {
  // Private constructor to prevent instantiation
  KitAction._(); // coverage:ignore-line

  // Track stream subscriptions by widgetId for cleanup
  static final Map<String, List<StreamSubscription>> _subscriptions = {};

  /// Execute an operation with automatic handling
  ///
  /// Returns a [KitActionBuilder] that can be configured with chainable methods.
  ///
  /// 📖 **Specification Reference:**
  ///    - Section 5.1: Main API Surface (lines 606-622)
  ///    - Section 6.1: Basic Patterns (PATTERN 1-9)
  ///
  /// **Parameters:**
  /// - [operation]: The operation to execute (sync or async)
  /// - [widgetId]: Unique identifier for the widget/operation (for error tracking)
  ///
  /// **Example:**
  /// ```dart
  /// await KitAction.run<String>(
  ///   operation: () async => 'result',
  ///   widgetId: 'my_view',
  /// )
  ///   .withLoading(setBusy)
  ///   .withErrorFallback('Failed', fallback: 'fallback')
  ///   .execute();
  /// ```
  static KitActionBuilder<T> run<T>({
    required FutureOr<T> Function() operation,
    required String widgetId,
  }) {
    return KitActionBuilder<T>(
      operation: operation,
      widgetId: widgetId,
    );
  }

  /// Watch reactive streams with automatic subscription management
  ///
  /// This is a compatibility method for migrating from KitAutoProcess.
  /// It sets up reactive listeners that trigger callbacks when stream values change.
  ///
  /// 📖 **Specification Reference:**
  ///    - Section 5.1: Main API Surface (lines 624-644)
  ///    - Section 6.1: PATTERN 9 (Reactive Stream)
  ///
  /// **Parameters:**
  /// - [widgetId]: Unique identifier for tracking subscriptions
  /// - [subjects]: List of BehaviorSubjects to watch
  /// - [callback]: Callback to execute when any subject emits a value
  /// - [errorMessage]: Optional error message for logging
  /// - [onError]: Optional error handler
  ///
  /// **Example:**
  /// ```dart
  /// KitAction.watch<User>(
  ///   widgetId: 'profile_view',
  ///   subjects: [userSubject$, settingsSubject$],
  ///   callback: rebuildUi,
  ///   errorMessage: 'Failed to watch user changes',
  /// );
  /// ```
  ///
  /// **Important:** Call [dispose] in your widget/viewmodel dispose method:
  /// ```dart
  /// @override
  /// void dispose() {
  ///   KitAction.dispose(widgetId: 'profile_view');
  ///   super.dispose();
  /// }
  /// ```
  static void watch<T>({
    required String widgetId,
    required List<BehaviorSubject<T>> subjects,
    required VoidCallback callback,
    String? errorMessage,
    Function(Exception, StackTrace)? onError,
  }) {
    final errorService = locator<KitErrorService>();

    // Subscribe to all subjects and call callback on emissions
    for (final subject in subjects) {
      final subscription = subject.listen(
        (_) {
          try {
            callback();
          } catch (e, stackTrace) {
            if (onError != null && e is Exception) {
              onError(e, stackTrace);
            } else {
              errorService.handle(
                exception: e,
                stackTrace: stackTrace,
                message: errorMessage ?? 'Error in stream watcher callback',
                widgetId: widgetId,
              );
            }
          }
        },
        onError: (error, stackTrace) {
          if (onError != null && error is Exception) {
            onError(error, stackTrace);
          } else {
            errorService.handle(
              exception: error,
              stackTrace: stackTrace,
              message: errorMessage ?? 'Error in stream',
              widgetId: widgetId,
            );
          }
        },
      );

      // Track subscription for later disposal
      _subscriptions.putIfAbsent(widgetId, () => []).add(subscription);
    }
  }

  /// Dispose subscriptions for a specific widget
  ///
  /// This is a compatibility method for migrating from KitAutoProcess.
  /// It cleans up all reactive subscriptions associated with the given widgetId.
  ///
  /// 📖 **Specification Reference:**
  ///    - Section 5.1: Main API Surface (lines 647-659)
  ///    - Section 9.1: Memory Management
  ///
  /// **Parameters:**
  /// - [widgetId]: The widget ID to dispose subscriptions for
  ///
  /// **Example:**
  /// ```dart
  /// @override
  /// void dispose() {
  ///   KitAction.dispose(widgetId: 'profile_view');
  ///   super.dispose();
  /// }
  /// ```
  static void dispose({required String widgetId}) {
    // Cancel all stream subscriptions for this widget
    final subscriptions = _subscriptions[widgetId];
    if (subscriptions != null) {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      _subscriptions.remove(widgetId);
    }

    // Also dispose any tracked subjects in StreamManager
    StreamManager.disposeWidget(widgetId);
  }
}
