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
///
/// The builder IS a [Future]: awaiting it runs the operation — there is no
/// terminal `.execute()` in app code. The execution is memoized, so multiple
/// `await`s/`then`s on the same builder share one run (the re-entry guard
/// stays happy). `execute()` remains for fire-and-forget assignment
/// (`final future = action(...).execute();`); `toStream()`/`toCancellable()`
/// are the single-call terminals for the reactive/cancellable forms.
class KitActionBuilder<T> implements Future<T> {
  final KitActionConfig<T> _config;

  /// Memoized execution future backing the [Future] interface — awaiting the
  /// builder twice must not run the operation twice.
  Future<T>? _awaited;

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
  // Future<T> — awaiting the builder executes the operation
  // ═════════════════════════════════════════════════════════════════════════

  Future<T> _asFuture() => _awaited ??= execute();

  @override
  Future<R> then<R>(FutureOr<R> Function(T value) onValue,
          {Function? onError}) =>
      _asFuture().then(onValue, onError: onError);

  @override
  Future<T> catchError(Function onError,
          {bool Function(Object error)? test}) =>
      _asFuture().catchError(onError, test: test);

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) =>
      _asFuture().whenComplete(action);

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) =>
      _asFuture().timeout(timeLimit, onTimeout: onTimeout);

  @override
  Stream<T> asStream() => _asFuture().asStream();

  // ═════════════════════════════════════════════════════════════════════════
  // Loading State Management
  // 📖 Spec: Section 5.2 (lines 669-698)
  // ═════════════════════════════════════════════════════════════════════════

  /// Set loading state callback (global busy state)
  ///
  /// Example:
  /// ```dart
  /// await KitAction.run<String>(...)
  ///   .withLoading(setBusy);
  /// ```
  KitActionBuilder<T> withLoading(void Function(bool isBusy) setBusy) {
    _config.setBusyCallback = setBusy;
    return this;
  }

  /// Set loading state for a specific object
  ///
  /// Example:
  /// ```dart
  /// await KitAction.run<String>(...)
  ///   .withLoadingFor(myObject, setBusyForObject);
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
  /// await KitAction.run<void>(
  ///   () async {
  ///     await _profileService.updateRole(role);
  ///   },
  ///   owner: this,
  ///   name: 'updateRole',
  /// )
  ///   .withLoading(setBusy)
  ///   .withClearLoadingBeforeSuccess()
  ///   .onSuccess((_) {
  ///     // Navigation happens here - view will dispose
  ///     _routerService.replaceWith(OnboardingViewRoute());
  ///   });
  /// ```
  KitActionBuilder<T> withClearLoadingBeforeSuccess() {
    _config.clearLoadingBeforeSuccess = true;
    return this;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Error Handling
  // 📖 Spec: Section 5.2 (lines 701-744)
  //
  // The two error APIs have distinct jobs:
  // - [completeOnError] decides the OUTCOME: the operation completes with the
  //   fallback value instead of throwing, and `message` becomes the error
  //   identity (log, error snackbar, state$ stream).
  // - [handleError] is a side-effect tap: run this when the operation fails.
  //   It changes nothing about the outcome.
  // ═════════════════════════════════════════════════════════════════════════

  /// Complete with a fallback on error instead of throwing
  ///
  /// Sets the error [message] (used by the error service log, the error
  /// snackbar, and the `state$` stream's errorMessage) and marks the
  /// operation as recovering: `await` completes with [withValue] (or `null`
  /// for `void`) instead of rethrowing.
  ///
  /// Example:
  /// ```dart
  /// await KitAction.run<String>(...)
  ///   .completeOnError('Failed to load user', withValue: 'anonymous');
  /// ```
  KitActionBuilder<T> completeOnError(
    String message, {
    T? withValue,
  }) {
    _config.errorMessage = message;
    _config.fallbackValue = withValue;
    _config.hasFallback = true;
    return this;
  }

  /// Side-effect tap executed when the operation fails
  ///
  /// Receives the thrown error (any [Object], not only [Exception]); the full
  /// stack trace is already logged by the error service before this runs.
  /// Changes nothing about the outcome — pair with [completeOnError] to also
  /// swallow the throw.
  ///
  /// Example:
  /// ```dart
  /// await KitAction.run<String>(...)
  ///   .handleError((error) => _errorMessage.add('$error'));
  /// ```
  KitActionBuilder<T> handleError(void Function(Object error) handler) {
    _config.handleErrorCallback = handler;
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
  /// await KitAction.run<String>(...)
  ///   .withLoadingSnackbar('Loading user...', title: 'Please wait');
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
  /// await KitAction.run<String>(...)
  ///   .withSuccessSnackbar('User loaded!', title: 'Success');
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
  /// await KitAction.run<String>(...)
  ///   .withErrorSnackbar('Failed to load user', title: 'Error');
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
  /// await KitAction.run<String>(...)
  ///   .withSnackbars(
  ///     loading: 'Loading...',
  ///     success: 'Success!',
  ///     error: 'Error!',
  ///   );
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
  /// await KitAction.run<String>(...)
  ///   .withNotificationType(NotificationType.dialog)
  ///   .withSnackbars(
  ///     loading: 'Saving...',
  ///     success: 'Saved!',
  ///     error: 'Failed to save',
  ///   );
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
  /// await KitAction.run<String>(...)
  ///   .withNotificationTypes(
  ///     loading: NotificationType.none,
  ///     success: NotificationType.snackbar,
  ///     error: NotificationType.dialog,
  ///   )
  ///   .withSnackbars(
  ///     success: 'Operation successful!',
  ///     error: 'An error occurred',
  ///   );
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
  /// await KitAction.run<String>(...)
  ///   .withDialogs()
  ///   .withSnackbars(
  ///     loading: 'Processing...',
  ///     success: 'Done!',
  ///     error: 'Failed',
  ///   );
  /// ```
  KitActionBuilder<T> withDialogs() {
    return withNotificationType(NotificationType.dialog);
  }

  /// Use bottom sheets for all notifications
  ///
  /// Example:
  /// ```dart
  /// await KitAction.run<String>(...)
  ///   .withBottomSheets()
  ///   .withSnackbars(
  ///     loading: 'Processing...',
  ///     success: 'Done!',
  ///     error: 'Failed',
  ///   );
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
  /// await KitAction.run<User>(...)
  ///   .onSuccess((user) => print('Loaded: ${user.name}'));
  ///
  /// // Async example (navigation)
  /// await KitAction.run<void>(...)
  ///   .onSuccess((_) async {
  ///     await _routerService.replaceWith(HomeRoute());
  ///   });
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
  /// await KitAction.run<String>(...)
  ///   .onComplete(() => print('Operation complete'));
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
  /// await KitAction.run<User>(...)
  ///   .onLoadingState((isLoading, message) {
  ///     setState(() {
  ///       _cardLoading = isLoading;
  ///       _cardMessage = message ?? '';
  ///     });
  ///   });
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
  /// await KitAction.run<User>(...)
  ///   .onSuccessState((message) {
  ///     setState(() {
  ///       _cardSuccessMessage = message;
  ///       _showSuccessIcon = true;
  ///     });
  ///   });
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
  /// await KitAction.run<User>(...)
  ///   .onErrorState((message) {
  ///     setState(() {
  ///       _inputError = message;
  ///       _inputValid = false;
  ///     });
  ///   });
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
  /// await KitAction.run<User>(...)
  ///   .withUIStateCallbacks(
  ///     onLoading: (isLoading, message) => setState(() => _loading = isLoading),
  ///     onSuccess: (message) => setState(() => _successText = message),
  ///     onError: (message) => setState(() => _errorText = message),
  ///   );
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
  /// await KitAction.run<String>(...)
  ///   .withRetry(
  ///     maxAttempts: 3,
  ///     delay: Duration(seconds: 1),
  ///     retryIf: (error) => error.toString().contains('network'),
  ///   );
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
  /// await KitAction.run<void>(...)
  ///   .withProgress((progress) {
  ///     _progress = progress;
  ///     rebuildUi();
  ///   });
  /// ```
  KitActionBuilder<T> withProgress(void Function(double progress) onProgress) {
    _config.onProgressCallback = onProgress;
    return this;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Reactive Streams
  // 📖 Spec: Section 5.2 (lines 1095-1136)
  // ═════════════════════════════════════════════════════════════════════════

  /// Execute the operation and return its result as a BehaviorSubject
  ///
  /// Single-call terminal — replaces the old `.asStream().executeAsStream()`
  /// pair. The subject closes itself with [withAutoCleanup] or dies with the
  /// owner's disposal.
  ///
  /// Example:
  /// ```dart
  /// final stream = KitAction.run<User>(...)
  ///   .toStream(initialValue: User.empty());
  /// ```
  BehaviorSubject<T> toStream({T? initialValue}) {
    _config.isStream = true;
    _config.streamInitialValue = initialValue;
    final executor = KitActionExecutor<T>(_config);
    return executor.executeAsStream();
  }

  /// Set up auto-cleanup trigger for streams
  ///
  /// Example:
  /// ```dart
  /// final stream = KitAction.run<User>(...)
  ///   .withAutoCleanup(disposeStream$)
  ///   .toStream();
  /// ```
  KitActionBuilder<T> withAutoCleanup(Stream<void> trigger) {
    _config.autoCleanupTrigger = trigger;
    return this;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Cancellation
  // 📖 Spec: Section 5.2 (lines 1141-1159)
  // ═════════════════════════════════════════════════════════════════════════

  /// Execute the operation as a cancellable operation
  ///
  /// Single-call terminal — replaces the old
  /// `.asCancellable().executeAsCancellable()` pair.
  ///
  /// Example:
  /// ```dart
  /// final cancellable = KitAction.run<String>(...)
  ///   .toCancellable();
  ///
  /// // Later...
  /// cancellable.cancel();
  /// ```
  KitActionCancellable<T> toCancellable() {
    _config.isCancellable = true;
    final executor = KitActionExecutor<T>(_config);
    return executor.executeAsCancellable();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Timeout
  // 📖 Spec: Section 5.2 (lines 1164-1177)
  // ═════════════════════════════════════════════════════════════════════════

  /// Set timeout for the operation
  ///
  /// Example:
  /// ```dart
  /// await KitAction.run<String>(...)
  ///   .withTimeout(Duration(seconds: 30));
  /// ```
  KitActionBuilder<T> withTimeout(Duration timeout) {
    _config.timeout = timeout;
    return this;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Re-entry Guard (default on — Flutter Command / command_it convention)
  // ═════════════════════════════════════════════════════════════════════════

  /// Allow parallel executions of the same widgetId
  ///
  /// By default KitAction prevents parallel runs: a second execution while
  /// the same widgetId is still in flight is dropped — it completes with the
  /// fallback when [completeOnError] was set, otherwise it throws a
  /// [GuardedException]. This is the double-tap protection the Flutter
  /// Command pattern and command_it build in. Call this to opt out for
  /// operations that are legitimately concurrent under one widgetId.
  ///
  /// Example:
  /// ```dart
  /// await KitAction.run<String>(...)
  ///   .withParallelExecution();
  /// ```
  KitActionBuilder<T> withParallelExecution() {
    _config.allowParallelExecution = true;
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
  /// await KitAction.run<List<String>>(...)
  ///   .withDebounce(Duration(milliseconds: 500));
  /// ```
  KitActionBuilder<T> withDebounce(Duration duration) {
    _config.debounceDuration = duration;
    return this;
  }

  /// Throttle operation execution (limit execution rate)
  ///
  /// Example:
  /// ```dart
  /// await KitAction.run<void>(...)
  ///   .withThrottle(Duration(milliseconds: 1000));
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
  ///   .withSnackbars(success: 'Done!');
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
  /// Escape hatch for fire-and-forget assignment — in app code prefer
  /// `await`ing the builder directly (it implements [Future]).
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
}
