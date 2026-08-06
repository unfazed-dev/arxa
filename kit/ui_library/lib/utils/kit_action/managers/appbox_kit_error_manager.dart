import 'package:appbox_kit_core/appbox_kit_locator.dart';
import 'package:appbox_kit_core/services/error/appbox_kit_error_service.dart';
import '../appbox_kit_action_config.dart';
import 'package:talker_flutter/talker_flutter.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AppBoxKitAction v2.0 - AppBoxKitErrorManager
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 4.2: Component Responsibilities - AppBoxKitErrorManager (lines 337-342)
//    - Section 5.2: Error Handling (lines 701-744)
//
// Intercepts errors, provides fallbacks, and coordinates error handling.
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages error handling for operations
/// Handles error logging, callbacks, and fallback values
class AppBoxKitErrorManager<T> {
  final AppBoxKitActionConfig<T> config;
  static final _errorService = appBoxKitLocator<AppBoxKitErrorService>();
  static final _talker = appBoxKitLocator<Talker>();

  AppBoxKitErrorManager(this.config);

  /// Handle error and return fallback value if available
  ///
  /// This method:
  /// 1. Logs the error via AppBoxKitErrorService
  /// 2. Calls custom error handler if provided
  /// 3. Returns fallback value if configured
  T? handleError(dynamic error, StackTrace stackTrace) {
    if (config.debugMode) {
      _talker.error(
        '[AppBoxKitAction] ⚠️ AppBoxKitErrorManager: Handling error for ${config.widgetId}',
        error,
        stackTrace,
      );
    }

    // 1. Log error via AppBoxKitErrorService
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
            '[AppBoxKitAction] 🔄 AppBoxKitErrorManager: Returning fallback value for ${config.widgetId}');
      }
      return config.fallbackValue;
    }

    if (config.debugMode) {
      _talker.warning(
          '[AppBoxKitAction] ❌ AppBoxKitErrorManager: No fallback available for ${config.widgetId}');
    }

    return null;
  }
}
