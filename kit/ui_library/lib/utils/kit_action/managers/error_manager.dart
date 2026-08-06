import 'package:appbox_kit_core/kit_locator.dart';
import 'package:appbox_kit_core/services/error/kit_error_service.dart';
import '../kit_action_config.dart';
import 'package:talker_flutter/talker_flutter.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// KitAction v2.0 - ErrorManager
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 4.2: Component Responsibilities - ErrorManager (lines 337-342)
//    - Section 5.2: Error Handling (lines 701-744)
//
// Intercepts errors, provides fallbacks, and coordinates error handling.
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages error handling for operations
/// Handles error logging, callbacks, and fallback values
class ErrorManager<T> {
  final KitActionConfig<T> config;
  static final _errorService = locator<KitErrorService>();
  static final _talker = locator<Talker>();

  ErrorManager(this.config);

  /// Handle error and return fallback value if available
  ///
  /// This method:
  /// 1. Logs the error via KitErrorService
  /// 2. Calls custom error handler if provided
  /// 3. Returns fallback value if configured
  T? handleError(dynamic error, StackTrace stackTrace) {
    if (config.debugMode) {
      _talker.error(
        '[KitAction] ⚠️ ErrorManager: Handling error for ${config.widgetId}',
        error,
        stackTrace,
      );
    }

    // 1. Log error via KitErrorService
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
            '[KitAction] 🔄 ErrorManager: Returning fallback value for ${config.widgetId}');
      }
      return config.fallbackValue;
    }

    if (config.debugMode) {
      _talker.warning(
          '[KitAction] ❌ ErrorManager: No fallback available for ${config.widgetId}');
    }

    return null;
  }
}
