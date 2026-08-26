// ignore_for_file: unused_element

import 'package:rxdart/rxdart.dart';
import '../arxa_kit_action_config.dart';
import '../arxa_kit_action_types.dart';
import 'arxa_kit_async_executor.dart';
import '../managers/arxa_kit_loading_manager.dart';
import '../managers/arxa_kit_error_manager.dart';
import '../managers/arxa_kit_success_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ArxaKitAction v2.0 - ArxaKitActionExecutor
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 4.2: Component Responsibilities - ArxaKitActionExecutor (lines 303-307)
//    - Section 4.1: High-Level Architecture (lines 236-287)
//
// Main orchestrator that delegates to specialized executors.
// ═══════════════════════════════════════════════════════════════════════════════

/// Main orchestrator for executing operations
/// Delegates to specialized executors based on operation type
class ArxaKitActionExecutor<T> {
  final ArxaKitActionConfig<T> config;

  ArxaKitActionExecutor(this.config);

  /// Execute the operation and return a Future
  Future<T> execute() async {
    // Use ArxaKitAsyncExecutor for all operations - it handles both sync and async
    final asyncExecutor = ArxaKitAsyncExecutor<T>(
      config: config,
      cancelToken: config.isCancellable ? ArxaKitCancelToken() : null,
    );
    return await asyncExecutor.execute();
  }

  // coverage:ignore-start
  /// Execute sync operation with basic handling
  T _executeSyncOperation(T result) {
    final loadingManager = ArxaKitLoadingManager<T>(config);
    final successManager = ArxaKitSuccessManager<T>(config);

    try {
      // 1. Start loading
      loadingManager.start();

      // 2. Handle success
      successManager.handleSuccess(result);

      return result;
    } finally {
      // 3. Stop loading
      loadingManager.stop();
    }
  }
  // coverage:ignore-end

  /// Execute the operation as a BehaviorSubject stream
  BehaviorSubject<T> executeAsStream() {
    // Create subject with initial value
    final subject = config.streamInitialValue != null
        ? BehaviorSubject<T>.seeded(config.streamInitialValue as T)
        : BehaviorSubject<T>();

    // Execute operation and add result to stream
    execute().then((result) {
      if (!subject.isClosed) {
        subject.add(result);
      }
    }).catchError((error, stackTrace) {
      if (!subject.isClosed) {
        // Handle error with fallback if available
        final errorManager = ArxaKitErrorManager<T>(config);
        final fallback = errorManager.handleError(error, stackTrace);

        if (fallback != null) {
          subject.add(fallback);
        } else {
          subject.addError(error, stackTrace);
        }
      }
    });

    // Auto-cleanup if configured
    if (config.autoCleanupTrigger != null) {
      config.autoCleanupTrigger!.listen((_) {
        if (!subject.isClosed) {
          subject.close();
        }
      });
    }

    return subject;
  }

  /// Execute the operation as a cancellable operation
  ArxaKitActionCancellable<T> executeAsCancellable() {
    final cancelToken = ArxaKitCancelToken();

    // Create async executor with cancel token
    final asyncExecutor = ArxaKitAsyncExecutor<T>(
      config: config,
      cancelToken: cancelToken,
    );

    // Execute operation through async executor
    final future = asyncExecutor.execute();

    return ArxaKitActionCancellable<T>(
      future: future,
      cancelToken: cancelToken,
    );
  }
}
