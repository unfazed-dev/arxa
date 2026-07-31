// ignore_for_file: unused_element

import 'package:rxdart/rxdart.dart';
import '../kit_action_config.dart';
import '../kit_action_types.dart';
import 'async_executor.dart';
import '../managers/loading_manager.dart';
import '../managers/error_manager.dart';
import '../managers/success_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// KitAction v2.0 - KitActionExecutor
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 4.2: Component Responsibilities - KitActionExecutor (lines 303-307)
//    - Section 4.1: High-Level Architecture (lines 236-287)
//
// Main orchestrator that delegates to specialized executors.
// ═══════════════════════════════════════════════════════════════════════════════

/// Main orchestrator for executing operations
/// Delegates to specialized executors based on operation type
class KitActionExecutor<T> {
  final KitActionConfig<T> config;

  KitActionExecutor(this.config);

  /// Execute the operation and return a Future
  Future<T> execute() async {
    // Use AsyncExecutor for all operations - it handles both sync and async
    final asyncExecutor = AsyncExecutor<T>(
      config: config,
      cancelToken: config.isCancellable ? CancelToken() : null,
    );
    return await asyncExecutor.execute();
  }

  // coverage:ignore-start
  /// Execute sync operation with basic handling
  T _executeSyncOperation(T result) {
    final loadingManager = LoadingManager<T>(config);
    final successManager = SuccessManager<T>(config);

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
        final errorManager = ErrorManager<T>(config);
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
  KitActionCancellable<T> executeAsCancellable() {
    final cancelToken = CancelToken();

    // Create async executor with cancel token
    final asyncExecutor = AsyncExecutor<T>(
      config: config,
      cancelToken: cancelToken,
    );

    // Execute operation through async executor
    final future = asyncExecutor.execute();

    return KitActionCancellable<T>(
      future: future,
      cancelToken: cancelToken,
    );
  }
}
