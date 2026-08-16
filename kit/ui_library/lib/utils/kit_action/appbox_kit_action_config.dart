import 'dart:async';
import 'appbox_kit_notification_type.dart';

/// Internal configuration class that stores all AppBoxKitAction settings
/// Built up by AppBoxKitActionBuilder and consumed by AppBoxKitActionExecutor
class AppBoxKitActionConfig<T> {
  /// The operation to execute
  final dynamic Function() operation;

  /// Unique identifier for the widget/operation
  final String widgetId;

  // ===== Loading State Management =====

  /// Callback to set busy state (global loading)
  void Function(bool isBusy)? setBusyCallback;

  /// Callback to set busy state for specific object
  void Function(Object object, bool isBusy)? setBusyForObjectCallback;

  /// Object to track loading state for
  Object? busyObject;

  /// Whether to clear loading state BEFORE success handlers run
  /// Useful for operations that navigate away from current view
  /// Prevents infinite spinner when view disposes before cleanup
  bool clearLoadingBeforeSuccess = false;

  // ===== Error Handling =====

  /// Error message to display/log — set by `completeOnError`
  String? errorMessage;

  /// Fallback value to return on error — set by `completeOnError(withValue:)`
  T? fallbackValue;

  /// Whether the operation completes with [fallbackValue] instead of throwing
  bool hasFallback = false;

  /// Side-effect tap executed on error — set by `handleError`
  void Function(Object error)? handleErrorCallback;

  // ===== Success Handling =====

  /// Callback executed on successful operation
  /// Supports both sync and async callbacks (navigation, state updates, etc.)
  FutureOr<void> Function(T result)? onSuccessCallback;

  /// Callback executed after operation completes (success or error)
  FutureOr<void> Function()? onCompleteCallback;

  // ===== Snackbar Notifications =====

  /// Loading snackbar message
  String? loadingSnackbarMessage;

  /// Loading snackbar title
  String? loadingSnackbarTitle;

  /// Loading snackbar duration
  Duration? loadingSnackbarDuration;

  /// Loading snackbar type
  dynamic loadingSnackbarType;

  /// Success snackbar message
  String? successSnackbarMessage;

  /// Success snackbar title
  String? successSnackbarTitle;

  /// Success snackbar duration
  Duration? successSnackbarDuration;

  /// Success snackbar type
  dynamic successSnackbarType;

  /// Error snackbar message
  String? errorSnackbarMessage;

  /// Error snackbar title
  String? errorSnackbarTitle;

  /// Error snackbar duration
  Duration? errorSnackbarDuration;

  /// Error snackbar type
  dynamic errorSnackbarType;

  // ===== Notification Types =====

  /// Type of notification for loading state (snackbar, dialog, bottomSheet, none)
  AppBoxKitNotificationType loadingNotificationType =
      AppBoxKitNotificationType.snackbar;

  /// Type of notification for success state (snackbar, dialog, bottomSheet, none)
  AppBoxKitNotificationType successNotificationType =
      AppBoxKitNotificationType.snackbar;

  /// Type of notification for error state (snackbar, dialog, bottomSheet, none)
  AppBoxKitNotificationType errorNotificationType =
      AppBoxKitNotificationType.snackbar;

  // ===== Retry Logic =====

  /// Maximum number of retry attempts
  int? retryMaxAttempts;

  /// Delay between retry attempts
  Duration? retryDelay;

  /// Predicate to determine if operation should be retried
  bool Function(Exception)? retryIf;

  // ===== Progress Tracking =====

  /// Callback for progress updates (0.0 to 1.0)
  void Function(double progress)? onProgressCallback;

  // ===== Granular UI State Callbacks =====

  /// Callback when loading state changes with message
  /// Use this to update specific UI components (cards, text inputs, etc.)
  void Function(bool isLoading, String? message)? onLoadingStateCallback;

  /// Callback when success occurs with message
  /// Use this to update specific UI components (cards, success text, etc.)
  void Function(String? message)? onSuccessStateCallback;

  /// Callback when error occurs with message
  /// Use this to update specific UI components (error text, validation, etc.)
  void Function(String? message)? onErrorStateCallback;

  // ===== Reactive Streams =====

  /// Whether this operation should return a stream
  bool isStream = false;

  /// Initial value for the stream
  T? streamInitialValue;

  /// Stream that triggers auto-cleanup
  Stream<void>? autoCleanupTrigger;

  // ===== Cancellation =====

  /// Whether this operation can be cancelled
  bool isCancellable = false;

  // ===== Timeout =====

  /// Timeout duration for the operation
  Duration? timeout;

  // ===== Re-entry Guard =====

  /// Whether parallel executions of the same widgetId are allowed.
  /// Defaults to false: an execute() while the same widgetId is still in
  /// flight is dropped — completes with [fallbackValue] when set, otherwise
  /// throws AppBoxKitGuardedException. Debounced chains are exempt by nature (a newer
  /// call cancels the pending one before either runs).
  bool allowParallelExecution = false;

  // ===== Debounce & Throttle =====

  /// Debounce duration (delay execution until no new calls)
  Duration? debounceDuration;

  /// Throttle duration (limit execution rate)
  Duration? throttleDuration;

  // ===== Debug Mode =====

  /// Enable debug mode for detailed logging (uses Talker)
  /// Logs execution flow, state changes, errors, and performance metrics
  bool debugMode = false;

  /// Creates a new AppBoxKitAction configuration
  AppBoxKitActionConfig({
    required this.operation,
    required this.widgetId,
  });
}
