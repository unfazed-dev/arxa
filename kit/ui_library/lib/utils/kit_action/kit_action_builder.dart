import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'kit_action_config.dart';
import 'kit_action_types.dart';
import 'notification_type.dart';
import 'executors/kit_action_executor.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// KitAction v2.0 - Fluent Builder
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 4.2: Component Responsibilities (KitActionBuilder)
//    - Section 5.2: Builder API - Complete Specification (lines 663-1299)
//
// This class implements the fluent builder pattern for configuring operations.
// All 30+ builder methods are documented in the specification with examples.
// ═══════════════════════════════════════════════════════════════════════════════

/// Fluent builder for configuring and executing operations
/// Provides a chainable API for adding features like loading, error handling, snackbars, etc.
class KitActionBuilder<T> {
  final KitActionConfig<T> _config;

  /// Internal constructor - use KitAction.run() as the entry point
  /// @nodoc
  KitActionBuilder({
    required dynamic Function() operation,
    required String widgetId,
  }) : _config = KitActionConfig<T>(
          operation: operation,
          widgetId: widgetId,
        );

  // ═════════════════════════════════════════════════════════════════════════
  // Loading State Management
  // 📖 Spec: Section 5.2 (lines 669-698)
  // ═════════════════════════════════════════════════════════════════════════

  /// Set loading state callback (global busy state)
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<String>(...)
  ///   .withLoading(setBusy)
  ///   .execute();
  /// ```
  KitActionBuilder<T> withLoading(void Function(bool isBusy) setBusy) {
    _config.setBusyCallback = setBusy;
    return this;
  }

  /// Set loading state for a specific object
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<String>(...)
  ///   .withLoadingFor(myObject, setBusyForObject)
  ///   .execute();
  /// ```
  KitActionBuilder<T> withLoadingFor(
    Object busyObject,
    void Function(Object object, bool isBusy) setBusyForObject,
  ) {
    _config.setBusyForObjectCallback = setBusyForObject;
    _config.busyObject = busyObject;
    return this;
  }

  /// Clear loading state BEFORE success handlers run
  /// Use this for operations that navigate away from current view
  /// Prevents infinite spinner when view disposes before cleanup
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<void>(
  ///   operation: () async {
  ///     await _profileService.updateRole(role);
  ///   },
  ///   widgetId: 'role_selection',
  /// )
  ///   .withLoading(setBusy)
  ///   .withClearLoadingBeforeSuccess()
  ///   .onSuccess((_) {
  ///     // Navigation happens here - view will dispose
  ///     _routerService.replaceWith(OnboardingViewRoute());
  ///   })
  ///   .execute();
  /// ```
  KitActionBuilder<T> withClearLoadingBeforeSuccess() {
    _config.clearLoadingBeforeSuccess = true;
    return this;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Error Handling
  // 📖 Spec: Section 5.2 (lines 701-744)
  // ═════════════════════════════════════════════════════════════════════════

  /// Set error message and optional fallback value
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<String>(...)
  ///   .withErrorFallback('Failed to load user', fallback: User.empty())
  ///   .execute();
  /// ```
  KitActionBuilder<T> withErrorFallback(
    String message, {
    T? fallback,
  }) {
    _config.errorMessage = message;
    _config.fallbackValue = fallback;
    _config.hasFallback = true;
    return this;
  }

  /// Set custom error handler callback
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<String>(...)
  ///   .onError((e, s) => print('Error: $e'))
  ///   .execute();
  /// ```
  KitActionBuilder<T> onError(
    void Function(Exception exception, StackTrace stackTrace) handler,
  ) {
    _config.onErrorCallback = handler;
    return this;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Notifications (Snackbars)
  // 📖 Spec: Section 5.2 (lines 769-854)
  // ═════════════════════════════════════════════════════════════════════════

  /// Show loading snackbar during operation
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<String>(...)
  ///   .withLoadingSnackbar('Loading user...', title: 'Please wait')
  ///   .execute();
  /// ```
  KitActionBuilder<T> withLoadingSnackbar(
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 2),
    dynamic type,
  }) {
    _config.loadingSnackbarMessage = message;
    _config.loadingSnackbarTitle = title;
    _config.loadingSnackbarDuration = duration;
    _config.loadingSnackbarType = type;
    return this;
  }

  /// Show success snackbar after successful operation
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<String>(...)
  ///   .withSuccessSnackbar('User loaded!', title: 'Success')
  ///   .execute();
  /// ```
  KitActionBuilder<T> withSuccessSnackbar(
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
    dynamic type,
  }) {
    _config.successSnackbarMessage = message;
    _config.successSnackbarTitle = title;
    _config.successSnackbarDuration = duration;
    _config.successSnackbarType = type;
    return this;
  }

  /// Show error snackbar on operation failure
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<String>(...)
  ///   .withErrorSnackbar('Failed to load user', title: 'Error')
  ///   .execute();
  /// ```
  KitActionBuilder<T> withErrorSnackbar(
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
    dynamic type,
  }) {
    _config.errorSnackbarMessage = message;
    _config.errorSnackbarTitle = title;
    _config.errorSnackbarDuration = duration;
    _config.errorSnackbarType = type;
    return this;
  }

  /// Convenience method to set all snackbar messages at once
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<String>(...)
  ///   .withSnackbars(
  ///     loading: 'Loading...',
  ///     success: 'Success!',
  ///     error: 'Error!',
  ///   )
  ///   .execute();
  /// ```
  KitActionBuilder<T> withSnackbars({
    String? loading,
    String? success,
    String? error,
    String? loadingTitle,
    String? successTitle,
    String? errorTitle,
    Duration? loadingDuration,
    Duration? successDuration,
    Duration? errorDuration,
  }) {
    if (loading != null) {
      withLoadingSnackbar(
        loading,
        title: loadingTitle,
        duration: loadingDuration ?? const Duration(seconds: 2),
      );
    }
    if (success != null) {
      withSuccessSnackbar(
        success,
        title: successTitle,
        duration: successDuration ?? const Duration(seconds: 3),
      );
    }
    if (error != null) {
      withErrorSnackbar(
        error,
        title: errorTitle,
        duration: errorDuration ?? const Duration(seconds: 3),
      );
    }
    return this;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Notification Types (NEW in v2.0)
  // 📖 Spec: Section 5.2 (lines 858-927)
  // ═════════════════════════════════════════════════════════════════════════

  /// Configure notification type for all states (loading, success, error)
  ///
  /// Example - Use dialogs for all notifications:
  /// ```dart
  /// KitAction.run<String>(...)
  ///   .withNotificationType(NotificationType.dialog)
  ///   .withSnackbars(
  ///     loading: 'Saving...',
  ///     success: 'Saved!',
  ///     error: 'Failed to save',
  ///   )
  ///   .execute();
  /// ```
  KitActionBuilder<T> withNotificationType(NotificationType type) {
    _config.loadingNotificationType = type;
    _config.successNotificationType = type;
    _config.errorNotificationType = type;
    return this;
  }

  /// Configure notification types individually for each state
  ///
  /// Example - Different types for different states:
  /// ```dart
  /// KitAction.run<String>(...)
  ///   .withNotificationTypes(
  ///     loading: NotificationType.none,
  ///     success: NotificationType.snackbar,
  ///     error: NotificationType.dialog,
  ///   )
  ///   .withSnackbars(
  ///     success: 'Operation successful!',
  ///     error: 'An error occurred',
  ///   )
  ///   .execute();
  /// ```
  KitActionBuilder<T> withNotificationTypes({
    NotificationType? loading,
    NotificationType? success,
    NotificationType? error,
  }) {
    if (loading != null) {
      _config.loadingNotificationType = loading;
    }
    if (success != null) {
      _config.successNotificationType = success;
    }
    if (error != null) {
      _config.errorNotificationType = error;
    }
    return this;
  }

  /// Use dialogs for all notifications
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<String>(...)
  ///   .withDialogs()
  ///   .withSnackbars(
  ///     loading: 'Processing...',
  ///     success: 'Done!',
  ///     error: 'Failed',
  ///   )
  ///   .execute();
  /// ```
  KitActionBuilder<T> withDialogs() {
    return withNotificationType(NotificationType.dialog);
  }

  /// Use bottom sheets for all notifications
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<String>(...)
  ///   .withBottomSheets()
  ///   .withSnackbars(
  ///     loading: 'Processing...',
  ///     success: 'Done!',
  ///     error: 'Failed',
  ///   )
  ///   .execute();
  /// ```
  KitActionBuilder<T> withBottomSheets() {
    return withNotificationType(NotificationType.bottomSheet);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // UI Callbacks
  // 📖 Spec: Section 5.2 (lines 933-967)
  // ═════════════════════════════════════════════════════════════════════════

  /// Callback executed on successful operation
  /// Supports both sync and async callbacks (navigation, state updates, etc.)
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<User>(...)
  ///   .onSuccess((user) => print('Loaded: ${user.name}'))
  ///   .execute();
  ///
  /// // Async example (navigation)
  /// KitAction.run<void>(...)
  ///   .onSuccess((_) async {
  ///     await _routerService.replaceWith(HomeRoute());
  ///   })
  ///   .execute();
  /// ```
  KitActionBuilder<T> onSuccess(FutureOr<void> Function(T result) callback) {
    _config.onSuccessCallback = callback;
    return this;
  }

  /// Callback executed after operation completes (success or error)
  /// Supports both sync and async callbacks
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<String>(...)
  ///   .onComplete(() => print('Operation complete'))
  ///   .execute();
  /// ```
  KitActionBuilder<T> onComplete(FutureOr<void> Function() callback) {
    _config.onCompleteCallback = callback;
    return this;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Granular UI State Callbacks (NEW in v2.0)
  // 📖 Spec: Section 5.2 (lines 972-1060)
  // ═════════════════════════════════════════════════════════════════════════

  /// Set callback for granular loading state updates
  /// Receives loading state and optional message for updating specific UI components
  ///
  /// Example - Update card loading state:
  /// ```dart
  /// KitAction.run<User>(...)
  ///   .onLoadingState((isLoading, message) {
  ///     setState(() {
  ///       _cardLoading = isLoading;
  ///       _cardMessage = message ?? '';
  ///     });
  ///   })
  ///   .execute();
  /// ```
  KitActionBuilder<T> onLoadingState(
    void Function(bool isLoading, String? message) callback,
  ) {
    _config.onLoadingStateCallback = callback;
    return this;
  }

  /// Set callback for granular success state updates
  /// Receives success message for updating specific UI components
  ///
  /// Example - Update success text in card:
  /// ```dart
  /// KitAction.run<User>(...)
  ///   .onSuccessState((message) {
  ///     setState(() {
  ///       _cardSuccessMessage = message;
  ///       _showSuccessIcon = true;
  ///     });
  ///   })
  ///   .execute();
  /// ```
  KitActionBuilder<T> onSuccessState(
    void Function(String? message) callback,
  ) {
    _config.onSuccessStateCallback = callback;
    return this;
  }

  /// Set callback for granular error state updates
  /// Receives error message for updating specific UI components
  ///
  /// Example - Update text input validation:
  /// ```dart
  /// KitAction.run<User>(...)
  ///   .onErrorState((message) {
  ///     setState(() {
  ///       _inputError = message;
  ///       _inputValid = false;
  ///     });
  ///   })
  ///   .execute();
  /// ```
  KitActionBuilder<T> onErrorState(
    void Function(String? message) callback,
  ) {
    _config.onErrorStateCallback = callback;
    return this;
  }

  /// Convenience method to set all UI state callbacks at once
  ///
  /// Example - Update card with all states:
  /// ```dart
  /// KitAction.run<User>(...)
  ///   .withUIStateCallbacks(
  ///     onLoading: (isLoading, msg) => setState(() => _loading = isLoading),
  ///     onSuccess: (msg) => setState(() => _successText = msg),
  ///     onError: (msg) => setState(() => _errorText = msg),
  ///   )
  ///   .execute();
  /// ```
  KitActionBuilder<T> withUIStateCallbacks({
    void Function(bool isLoading, String? message)? onLoading,
    void Function(String? message)? onSuccess,
    void Function(String? message)? onError,
  }) {
    if (onLoading != null) {
      _config.onLoadingStateCallback = onLoading;
    }
    if (onSuccess != null) {
      _config.onSuccessStateCallback = onSuccess;
    }
    if (onError != null) {
      _config.onErrorStateCallback = onError;
    }
    return this;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Retry Logic
  // 📖 Spec: Section 5.2 (lines 748-765)
  // ═════════════════════════════════════════════════════════════════════════

  /// Configure retry behavior for failed operations
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<String>(...)
  ///   .withRetry(
  ///     maxAttempts: 3,
  ///     delay: Duration(seconds: 1),
  ///     retryIf: (e) => e.toString().contains('network'),
  ///   )
  ///   .execute();
  /// ```
  KitActionBuilder<T> withRetry({
    int maxAttempts = 3,
    Duration delay = const Duration(seconds: 1),
    bool Function(Exception)? retryIf,
  }) {
    _config.retryMaxAttempts = maxAttempts;
    _config.retryDelay = delay;
    _config.retryIf = retryIf;
    return this;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Progress Tracking
  // 📖 Spec: Section 5.2 (lines 1067-1090)
  // ═════════════════════════════════════════════════════════════════════════

  /// Track progress of long-running operations (0.0 to 1.0)
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<void>(...)
  ///   .withProgress((progress) {
  ///     _progress = progress;
  ///     rebuildUi();
  ///   })
  ///   .execute();
  /// ```
  KitActionBuilder<T> withProgress(void Function(double progress) onProgress) {
    _config.onProgressCallback = onProgress;
    return this;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Reactive Streams
  // 📖 Spec: Section 5.2 (lines 1095-1136)
  // ═════════════════════════════════════════════════════════════════════════

  /// Configure operation to return a BehaviorSubject stream
  ///
  /// Example:
  /// ```dart
  /// final stream = KitAction.run<User>(...)
  ///   .asStream(initialValue: User.empty())
  ///   .executeAsStream();
  /// ```
  KitActionBuilder<T> asStream({T? initialValue}) {
    _config.isStream = true;
    _config.streamInitialValue = initialValue;
    return this;
  }

  /// Set up auto-cleanup trigger for streams
  ///
  /// Example:
  /// ```dart
  /// final stream = KitAction.run<User>(...)
  ///   .asStream()
  ///   .withAutoCleanup(disposeStream$)
  ///   .executeAsStream();
  /// ```
  KitActionBuilder<T> withAutoCleanup(Stream<void> trigger) {
    _config.autoCleanupTrigger = trigger;
    return this;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Cancellation
  // 📖 Spec: Section 5.2 (lines 1141-1159)
  // ═════════════════════════════════════════════════════════════════════════

  /// Configure operation as cancellable
  ///
  /// Example:
  /// ```dart
  /// final cancellable = KitAction.run<String>(...)
  ///   .asCancellable()
  ///   .executeAsCancellable();
  ///
  /// // Later...
  /// cancellable.cancel();
  /// ```
  KitActionBuilder<T> asCancellable() {
    _config.isCancellable = true;
    return this;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Timeout
  // 📖 Spec: Section 5.2 (lines 1164-1177)
  // ═════════════════════════════════════════════════════════════════════════

  /// Set timeout for the operation
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<String>(...)
  ///   .withTimeout(Duration(seconds: 30))
  ///   .execute();
  /// ```
  KitActionBuilder<T> withTimeout(Duration timeout) {
    _config.timeout = timeout;
    return this;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Debounce & Throttle
  // 📖 Spec: Section 5.2 (lines 1181-1209)
  // ═════════════════════════════════════════════════════════════════════════

  /// Debounce operation execution (delay until no new calls)
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<List<String>>(...)
  ///   .withDebounce(Duration(milliseconds: 500))
  ///   .execute();
  /// ```
  KitActionBuilder<T> withDebounce(Duration duration) {
    _config.debounceDuration = duration;
    return this;
  }

  /// Throttle operation execution (limit execution rate)
  ///
  /// Example:
  /// ```dart
  /// KitAction.run<void>(...)
  ///   .withThrottle(Duration(milliseconds: 1000))
  ///   .execute();
  /// ```
  KitActionBuilder<T> withThrottle(Duration duration) {
    _config.throttleDuration = duration;
    return this;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Debug Mode (NEW in v2.0)
  // 📖 Spec: Section 5.2 (lines 1214-1251)
  // ═════════════════════════════════════════════════════════════════════════

  /// Enable debug mode for detailed logging using Talker
  ///
  /// Logs will include:
  /// - Execution flow (start, retries, completion)
  /// - Loading state changes
  /// - Success/error handling
  /// - Notification display
  /// - Performance metrics (execution time)
  /// - Manager activities (LoadingManager, ErrorManager, etc.)
  ///
  /// Logs appear in:
  /// - Console (CLI)
  /// - Talker UI in-app (when using TalkerScreen)
  ///
  /// Example:
  /// ```dart
  /// await KitAction.run<String>(...)
  ///   .withDebugMode()
  ///   .withRetry(maxAttempts: 3)
  ///   .withSnackbars(success: 'Done!')
  ///   .execute();
  /// ```
  KitActionBuilder<T> withDebugMode() {
    _config.debugMode = true;
    return this;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Terminal Operations
  // 📖 Spec: Section 5.2 (lines 1257-1299)
  // ═════════════════════════════════════════════════════════════════════════

  /// Execute the operation and return a Future
  ///
  /// Example:
  /// ```dart
  /// final result = await KitAction.run<String>(...)
  ///   .withLoading(setBusy)
  ///   .execute();
  /// ```
  Future<T> execute() {
    final executor = KitActionExecutor<T>(_config);
    return executor.execute();
  }

  /// Execute the operation and return a BehaviorSubject stream
  /// Must call `.asStream()` first or this will throw a StateError
  ///
  /// Example:
  /// ```dart
  /// final stream = KitAction.run<User>(...)
  ///   .asStream(initialValue: User.empty())
  ///   .executeAsStream();
  /// ```
  BehaviorSubject<T> executeAsStream() {
    if (!_config.isStream) {
      throw StateError(
        'Cannot execute as stream. Call .asStream() first.',
      );
    }
    final executor = KitActionExecutor<T>(_config);
    return executor.executeAsStream();
  }

  /// Execute the operation as a cancellable operation
  /// Must call `.asCancellable()` first or this will throw a StateError
  ///
  /// Example:
  /// ```dart
  /// final cancellable = KitAction.run<String>(...)
  ///   .asCancellable()
  ///   .executeAsCancellable();
  ///
  /// cancellable.cancel();
  /// ```
  KitActionCancellable<T> executeAsCancellable() {
    if (!_config.isCancellable) {
      throw StateError(
        'Cannot execute as cancellable. Call .asCancellable() first.',
      );
    }
    final executor = KitActionExecutor<T>(_config);
    return executor.executeAsCancellable();
  }
}
