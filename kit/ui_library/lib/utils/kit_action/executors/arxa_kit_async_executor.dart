import 'dart:async';
import 'package:arxa_kit_core/arxa_kit_locator.dart';
import '../arxa_kit_action_config.dart';
import '../arxa_kit_action_types.dart';
import '../managers/arxa_kit_loading_manager.dart';
import '../managers/arxa_kit_error_manager.dart';
import '../managers/arxa_kit_success_manager.dart';
import '../managers/arxa_kit_notification_manager.dart';
import '../managers/arxa_kit_action_state_manager.dart';
import 'package:talker_flutter/talker_flutter.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ArxaKitAction v2.0 - ArxaKitAsyncExecutor
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 4.2: Component Responsibilities - ArxaKitAsyncExecutor (lines 308-311)
//    - Section 5.2: Retry, Timeout, Debounce, Throttle (lines 748-1209)
//
// Executes async operations with retry, timeout, cancellation, debounce/throttle.
// ═══════════════════════════════════════════════════════════════════════════════

/// Executes async operations with full feature support
/// Handles loading, errors, retry, timeout, cancellation, debounce, throttle
class ArxaKitAsyncExecutor<T> {
  final ArxaKitActionConfig<T> config;
  late final ArxaKitLoadingManager<T> loadingManager;
  late final ArxaKitErrorManager<T> errorManager;
  late final ArxaKitSuccessManager<T> successManager;
  late final ArxaKitNotificationManager<T> notificationManager;
  final ArxaKitCancelToken? cancelToken;
  static final _talker = arxaKitLocator<Talker>();

  /// Static map to track debounce timers and completers by widgetId
  static final Map<String, Timer> _debounceTimers = {};
  static final Map<String, Completer> _debounceCompleters = {};

  /// Static map to track last throttle execution time by widgetId
  static final Map<String, DateTime> _throttleLastExecution = {};

  /// Static set of widgetIds currently executing (re-entry guard)
  static final Set<String> _inFlight = {};

  ArxaKitAsyncExecutor({
    required this.config,
    ArxaKitLoadingManager<T>? loadingManager,
    ArxaKitErrorManager<T>? errorManager,
    ArxaKitSuccessManager<T>? successManager,
    ArxaKitNotificationManager<T>? notificationManager,
    this.cancelToken,
  }) {
    this.loadingManager = loadingManager ?? ArxaKitLoadingManager<T>(config);
    this.errorManager = errorManager ?? ArxaKitErrorManager<T>(config);
    this.successManager = successManager ?? ArxaKitSuccessManager<T>(config);
    this.notificationManager =
        notificationManager ?? ArxaKitNotificationManager<T>(config);
  }

  /// Execute the async operation with all features
  /// Calls config.operation() internally to enable proper retry logic
  /// Applies debounce or throttle if configured
  Future<T> execute() async {
    if (config.debugMode) {
      _talker.debug(
        '[ArxaKitAction] 🚀 Starting execution for widgetId: ${config.widgetId}',
      );
    }

    // Apply debounce if configured
    if (config.debounceDuration != null) {
      if (config.debugMode) {
        _talker.debug(
          '[ArxaKitAction] ⏱️ Debounce mode: ${config.debounceDuration} for ${config.widgetId}',
        );
      }
      return _executeWithDebounce();
    }

    // Apply throttle if configured
    if (config.throttleDuration != null) {
      if (config.debugMode) {
        _talker.debug(
          '[ArxaKitAction] 🚦 Throttle mode: ${config.throttleDuration} for ${config.widgetId}',
        );
      }
      return _executeWithThrottle();
    }

    // Normal execution
    if (config.debugMode) {
      _talker.debug(
          '[ArxaKitAction] ▶️ Normal execution for ${config.widgetId}');
    }
    return _executeNormal();
  }

  /// Execute the operation without debounce/throttle
  Future<T> _executeNormal() async {
    final stopwatch = config.debugMode ? (Stopwatch()..start()) : null;

    // Re-entry guard (default): drop overlapping executions of the same
    // widgetId. Thrown here, before the try, so a dropped call never routes
    // into the error/notification path — a double-tap is not an error.
    final guarded = !config.allowParallelExecution;
    if (guarded) {
      if (_inFlight.contains(config.widgetId)) {
        if (config.debugMode) {
          _talker.warning(
              '[ArxaKitAction] 🛡️ Re-entry dropped for ${config.widgetId}');
        }
        if (config.hasFallback) return config.fallbackValue as T;
        throw ArxaKitGuardedException(
          'ArxaKitAction "${config.widgetId}" is already running — overlapping call dropped',
        );
      }
      _inFlight.add(config.widgetId);
    }

    try {
      // 1. Set loading state
      if (config.debugMode) {
        _talker.debug(
            '[ArxaKitAction] 🔄 Setting loading state for ${config.widgetId}');
      }
      _startLoading();

      // 2. Check if already cancelled
      if (cancelToken?.isCancelled == true) {
        if (config.debugMode) {
          _talker.warning(
              '[ArxaKitAction] ❌ Operation already cancelled for ${config.widgetId}');
        }
        throw ArxaKitCancelledException();
      }

      // 3. Execute with retry if configured
      T result;
      if (config.retryMaxAttempts != null && config.retryMaxAttempts! > 1) {
        if (config.debugMode) {
          _talker.debug(
            '[ArxaKitAction] 🔁 Retry enabled: ${config.retryMaxAttempts} attempts for ${config.widgetId}',
          );
        }
        result = await _executeWithRetry();
      } else {
        if (config.debugMode) {
          _talker.debug(
              '[ArxaKitAction] ⚡ Executing operation for ${config.widgetId}');
        }
        result = await _executeSingleAttempt();
      }

      // 4. Check cancellation before success handling
      if (cancelToken?.isCancelled == true) {
        if (config.debugMode) {
          _talker.warning(
              '[ArxaKitAction] ❌ Operation cancelled after execution for ${config.widgetId}');
        }
        throw ArxaKitCancelledException();
      }

      // 5. Clear loading BEFORE success if configured (for navigation flows)
      if (config.clearLoadingBeforeSuccess) {
        if (config.debugMode) {
          _talker.debug(
              '[ArxaKitAction] 🔄 Clearing loading BEFORE success handlers for ${config.widgetId}');
        }
        _stopLoading();
      }

      // 6. Handle success
      if (config.debugMode) {
        _talker.info(
            '[ArxaKitAction] ✅ Operation succeeded for ${config.widgetId}');
      }
      await _handleSuccess(result);

      if (config.debugMode) {
        stopwatch?.stop();
        _talker.info(
          '[ArxaKitAction] ⏱️ Execution time: ${stopwatch?.elapsedMilliseconds}ms for ${config.widgetId}',
        );
      }

      return result;
    } catch (e, s) {
      // 7. Handle error
      if (config.debugMode) {
        stopwatch?.stop();
        _talker.error(
          '[ArxaKitAction] ⚠️ Operation failed for ${config.widgetId}',
          e,
          s,
        );
        _talker.info(
          '[ArxaKitAction] ⏱️ Failed after: ${stopwatch?.elapsedMilliseconds}ms for ${config.widgetId}',
        );
      }
      return _handleError(e, s);
    } finally {
      if (guarded) _inFlight.remove(config.widgetId);
      // 8. Always reset loading state (ArxaKitLoadingManager handles redundant calls)
      if (config.debugMode) {
        _talker.debug(
            '[ArxaKitAction] 🔄 Resetting loading state for ${config.widgetId}');
      }
      _stopLoading();
    }
  }

  /// Execute operation with debounce (delay execution until no new calls)
  Future<T> _executeWithDebounce() async {
    final completer = Completer<T>();

    // Cancel previous timer for this widgetId and complete with error
    final previousTimer = _debounceTimers[config.widgetId];
    final previousCompleter = _debounceCompleters[config.widgetId];

    if (previousTimer != null) {
      previousTimer.cancel();

      // Complete previous completer with fallback or error
      if (previousCompleter != null && !previousCompleter.isCompleted) {
        // If there's a fallback, use it; otherwise throw cancellation error
        if (config.hasFallback) {
          previousCompleter.complete(config.fallbackValue);
        } else {
          previousCompleter.completeError(
            Exception('Debounced - operation cancelled by newer call'),
          );
        }
      }
    }

    // Store new completer
    _debounceCompleters[config.widgetId] = completer;

    // Create new timer
    _debounceTimers[config.widgetId] =
        Timer(config.debounceDuration!, () async {
      try {
        final result = await _executeNormal();
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (e, s) {
        if (!completer.isCompleted) {
          completer.completeError(e, s);
        }
      } finally {
        // Clean up timer and completer references
        _debounceTimers.remove(config.widgetId);
        _debounceCompleters.remove(config.widgetId);
      }
    });

    return completer.future;
  }

  /// Execute operation with throttle (limit execution rate)
  Future<T> _executeWithThrottle() async {
    final now = DateTime.now();
    final lastExecution = _throttleLastExecution[config.widgetId];

    if (lastExecution != null) {
      final elapsed = now.difference(lastExecution);
      if (elapsed < config.throttleDuration!) {
        // Too soon - throw throttle exception
        throw ArxaKitThrottledException(
          'Operation throttled. Please wait ${config.throttleDuration!.inMilliseconds - elapsed.inMilliseconds}ms',
        );
      }
    }

    // Update last execution time
    _throttleLastExecution[config.widgetId] = now;

    // Execute normally
    return _executeNormal();
  }

  /// Execute a single attempt of the operation
  Future<T> _executeSingleAttempt() async {
    final result = config.operation();

    // Handle sync vs async
    if (result is Future<T>) {
      // Apply timeout if configured
      if (config.timeout != null) {
        return await result.timeout(config.timeout!);
      }
      return await result;
    } else {
      return result as T;
    }
  }

  /// Execute operation with retry logic
  Future<T> _executeWithRetry() async {
    int attempts = 0;
    final maxAttempts = config.retryMaxAttempts ?? 1;

    while (attempts < maxAttempts) {
      try {
        attempts++;
        if (config.debugMode) {
          _talker.debug(
            '[ArxaKitAction] 🔁 Attempt $attempts/$maxAttempts for ${config.widgetId}',
          );
        }

        // Execute the operation (re-execute for each retry)
        return await _executeSingleAttempt();
      } catch (e) {
        // Check if we should retry
        final isLastAttempt = attempts >= maxAttempts;

        if (isLastAttempt) {
          if (config.debugMode) {
            _talker.warning(
              '[ArxaKitAction] ❌ All retry attempts exhausted for ${config.widgetId}',
            );
          }
          rethrow; // Last attempt failed, propagate error
        }

        // Check retry condition if provided
        if (config.retryIf != null) {
          final exception = e is Exception ? e : Exception(e.toString());
          final shouldRetry = config.retryIf!(exception);

          if (!shouldRetry) {
            if (config.debugMode) {
              _talker.warning(
                '[ArxaKitAction] ⚠️ Retry condition not met, aborting retries for ${config.widgetId}',
              );
            }
            rethrow; // Condition says don't retry
          }
        }

        if (config.debugMode) {
          _talker.warning(
            '[ArxaKitAction] ⏳ Attempt $attempts failed, retrying for ${config.widgetId}...',
          );
        }

        // Wait before retry
        if (config.retryDelay != null) {
          if (config.debugMode) {
            _talker.debug(
              '[ArxaKitAction] ⏱️ Waiting ${config.retryDelay} before retry for ${config.widgetId}',
            );
          }
          await Future.delayed(config.retryDelay!);
        }
      }
    }

    // Should never reach here, but satisfies return type
    throw Exception('Retry logic error'); // coverage:ignore-line
  }

  /// Start loading state
  void _startLoading() {
    ArxaKitActionStateManager.markBusy(config.widgetId);
    loadingManager.start();
    notificationManager.showLoadingSnackbar();
  }

  /// Stop loading state
  void _stopLoading() {
    ArxaKitActionStateManager.markDone(config.widgetId);
    loadingManager.stop();
  }

  /// Handle successful operation
  Future<void> _handleSuccess(T result) async {
    await successManager.handleSuccess(result);
    notificationManager.showSuccessSnackbar();
  }

  /// Handle operation error
  Future<T> _handleError(dynamic error, StackTrace stackTrace) async {
    final fallback = errorManager.handleError(error, stackTrace);
    ArxaKitActionStateManager.markError(
      config.widgetId,
      // The user-facing message, however it was configured: explicit
      // completeOnError message, else the error snackbar's, else the raw
      // exception.
      config.errorMessage ?? config.errorSnackbarMessage ?? error.toString(),
    );
    notificationManager.showErrorSnackbar();

    if (config.hasFallback) {
      return fallback as T;
    }

    // Rethrow if no fallback
    if (error is Exception) {
      throw error;
    } else {
      throw Exception(error.toString());
    }
  }
}
