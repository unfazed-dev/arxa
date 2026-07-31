import 'package:appbox_kit_core/kit_locator.dart';
import 'package:appbox_kit_core/services/error/kit_error_service.dart';
import '../kit_action_config.dart';
import 'package:talker_flutter/talker_flutter.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// KitAction v2.0 - SuccessManager
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 4.2: Component Responsibilities - SuccessManager (lines 329-335)
//    - Section 4.3: SuccessManager Detailed Specification (lines 360-592)
//
// Orchestrates success callbacks, UI updates, and side-effects.
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages success handling for operations
/// Executes success and complete callbacks with error isolation
class SuccessManager<T> {
  final KitActionConfig<T> config;
  static final _errorService = locator<KitErrorService>();
  static final _talker = locator<Talker>();

  SuccessManager(this.config);

  /// Handle successful operation
  ///
  /// Executes both onSuccess and onComplete callbacks with error isolation.
  /// Errors in one callback do not prevent other callbacks from executing.
  Future<void> handleSuccess(T result) async {
    if (config.debugMode) {
      _talker.info(
          '[KitAction] ✅ SuccessManager: Handling success for ${config.widgetId}');
    }

    try {
      // 1. Execute onSuccess callback
      if (config.onSuccessCallback != null) {
        if (config.debugMode) {
          _talker.debug(
              '[KitAction] 📢 SuccessManager: Calling onSuccess callback for ${config.widgetId}');
        }
        try {
          // Await the callback to support async operations like navigation
          await config.onSuccessCallback!(result);
        } catch (e, s) {
          _errorService.warning(
            error: e,
            stackTrace: s,
            message: 'Error in onSuccess callback',
            widgetId: config.widgetId,
          );
        }
      }

      // 2. Execute granular UI state callback for success
      if (config.onSuccessStateCallback != null) {
        try {
          config.onSuccessStateCallback!(config.successSnackbarMessage);
        } catch (e, s) {
          _errorService.warning(
            error: e,
            stackTrace: s,
            message: 'Error in onSuccessState callback',
            widgetId: config.widgetId,
          );
        }
      }

      // 3. Execute onComplete callback
      if (config.onCompleteCallback != null) {
        try {
          await config.onCompleteCallback!();
        } catch (e, s) {
          _errorService.warning(
            error: e,
            stackTrace: s,
            message: 'Error in onComplete callback',
            widgetId: config.widgetId,
          );
        }
      }
    } catch (e, s) {
      _errorService.handle(
        exception: e,
        stackTrace: s,
        message: 'Error in SuccessManager',
        widgetId: config.widgetId,
      );
    }
  }
}
