import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_core/services/error/arxa_kit_error_service.dart';
import '../arxa_kit_action_config.dart';
import 'package:talker_flutter/talker_flutter.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ArxaKitAction v2.0 - ArxaKitErrorManager
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 4.2: Component Responsibilities - ArxaKitErrorManager (lines 337-342)
//    - Section 5.2: Error Handling (lines 701-744)
//
// Intercepts errors, provides fallbacks, and coordinates error handling.
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages error handling for operations
/// Handles error logging, callbacks, and fallback values
class ArxaKitErrorManager<T> {
  final ArxaKitActionConfig<T> config;
  static final _errorService = arxaKitLocator<ArxaKitErrorService>();
  static final _talker = arxaKitLocator<Talker>();

  ArxaKitErrorManager(this.config);

  /// Handle error and return fallback value if available
  ///
  /// This method:
  /// 1. Logs the error via ArxaKitErrorService
  /// 2. Calls custom error handler if provided
  /// 3. Returns fallback value if configured
  T? handleError(dynamic error, StackTrace stackTrace) {
    if (config.debugMode) {
      _talker.error(
        '[ArxaKitAction] ⚠️ ArxaKitErrorManager: Handling error for ${config.widgetId}',
        error,
        stackTrace,
      );
    }

    // 1. Log error via ArxaKitErrorService
    _errorService.handle(
      exception: error,
      stackTrace: stackTrace,
      message: config.errorMessage ?? 'Operation failed',
      widgetId: config.widgetId,
    );

    // 2. Call the side-effect error tap if provided
    if (config.handleErrorCallback != null) {
      try {
        config.handleErrorCallback!(error);
      } catch (handlerError, handlerStackTrace) {
        _errorService.warning(
          error: handlerError,
          stackTrace: handlerStackTrace,
          message: 'Error in custom error handler',
          widgetId: config.widgetId,
        );
      }
    }

    // 3. Call granular UI state callback for error
    if (config.onErrorStateCallback != null) {
      try {
        config.onErrorStateCallback!(
          config.errorSnackbarMessage ?? config.errorMessage,
        );
      } catch (handlerError, handlerStackTrace) {
        _errorService.warning(
          error: handlerError,
          stackTrace: handlerStackTrace,
          message: 'Error in onErrorState callback',
          widgetId: config.widgetId,
        );
      }
    }

    // 4. Return fallback value if available
    if (config.hasFallback) {
      if (config.debugMode) {
        _talker.info(
            '[ArxaKitAction] 🔄 ArxaKitErrorManager: Returning fallback value for ${config.widgetId}');
      }
      return config.fallbackValue;
    }

    if (config.debugMode) {
      _talker.warning(
          '[ArxaKitAction] ❌ ArxaKitErrorManager: No fallback available for ${config.widgetId}');
    }

    return null;
  }
}
