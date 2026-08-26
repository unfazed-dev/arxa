import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_core/services/error/arxa_kit_error_service.dart';
import '../../../services/notifications/arxa_kit_notification_service.dart';
import '../arxa_kit_action_config.dart';
import '../arxa_kit_notification_type.dart';
import 'package:talker_flutter/talker_flutter.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ArxaKitAction v2.0 - ArxaKitNotificationManager
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 4.2: Component Responsibilities - ArxaKitNotificationManager (lines 344-351)
//    - Section 5.2: Notifications & Types (lines 769-927)
//
// Manages user notifications with multiple display types (NEW in v2.0).
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages notifications for operations (snackbars, dialogs, bottom sheets)
/// Handles loading, success, and error notifications based on configured type
class ArxaKitNotificationManager<T> {
  final ArxaKitActionConfig<T> config;
  static final _errorService = arxaKitLocator<ArxaKitErrorService>();
  static final _talker = arxaKitLocator<Talker>();

  ArxaKitNotificationManager(this.config);

  /// Show loading notification based on configured type
  void showLoadingSnackbar() {
    if (config.loadingSnackbarMessage == null) return;

    if (config.debugMode) {
      _talker.debug(
        '[ArxaKitAction] 🔔 ArxaKitNotificationManager: Showing loading notification (${config.loadingNotificationType.name}) for ${config.widgetId}',
      );
    }

    try {
      switch (config.loadingNotificationType) {
        case ArxaKitNotificationType.snackbar:
          arxaKitLocator<ArxaKitNotificationService>().show(
            config.loadingSnackbarMessage!,
            kind: ArxaKitNotificationKind.info,
            title: config.loadingSnackbarTitle,
            variant: config.loadingSnackbarType,
            duration:
                config.loadingSnackbarDuration ?? const Duration(seconds: 2),
          );
          break;

        case ArxaKitNotificationType.dialog:
          arxaKitLocator<ArxaKitNotificationService>().alert(
            title: config.loadingSnackbarTitle ?? 'Loading',
            message: config.loadingSnackbarMessage!,
            barrierDismissible: false,
          );
          break;

        case ArxaKitNotificationType.bottomSheet:
          arxaKitLocator<ArxaKitNotificationService>().notice(
            title: config.loadingSnackbarTitle ?? 'Loading',
            message: config.loadingSnackbarMessage!,
          );
          break;

        case ArxaKitNotificationType.none:
          // Do nothing
          break;
      }
    } catch (e, s) {
      _errorService.warning(
        error: e,
        stackTrace: s,
        message: 'Failed to show loading notification',
        widgetId: config.widgetId,
      );
    }
  }

  /// Show success notification based on configured type
  void showSuccessSnackbar() {
    if (config.successSnackbarMessage == null) return;

    if (config.debugMode) {
      _talker.info(
        '[ArxaKitAction] ✅ ArxaKitNotificationManager: Showing success notification (${config.successNotificationType.name}) for ${config.widgetId}',
      );
    }

    try {
      switch (config.successNotificationType) {
        case ArxaKitNotificationType.snackbar:
          arxaKitLocator<ArxaKitNotificationService>().show(
            config.successSnackbarMessage!,
            kind: ArxaKitNotificationKind.success,
            title: config.successSnackbarTitle,
            variant: config.successSnackbarType,
            duration:
                config.successSnackbarDuration ?? const Duration(seconds: 3),
          );
          break;

        case ArxaKitNotificationType.dialog:
          arxaKitLocator<ArxaKitNotificationService>().alert(
            title: config.successSnackbarTitle ?? 'Success',
            message: config.successSnackbarMessage!,
          );
          break;

        case ArxaKitNotificationType.bottomSheet:
          arxaKitLocator<ArxaKitNotificationService>().notice(
            title: config.successSnackbarTitle ?? 'Success',
            message: config.successSnackbarMessage!,
          );
          break;

        case ArxaKitNotificationType.none:
          // Do nothing
          break;
      }
    } catch (e, s) {
      _errorService.warning(
        error: e,
        stackTrace: s,
        message: 'Failed to show success notification',
        widgetId: config.widgetId,
      );
    }
  }

  /// Show error notification based on configured type
  void showErrorSnackbar() {
    if (config.errorSnackbarMessage == null) return;

    if (config.debugMode) {
      _talker.error(
        '[ArxaKitAction] ⚠️ ArxaKitNotificationManager: Showing error notification (${config.errorNotificationType.name}) for ${config.widgetId}',
      );
    }

    try {
      switch (config.errorNotificationType) {
        case ArxaKitNotificationType.snackbar:
          arxaKitLocator<ArxaKitNotificationService>().show(
            config.errorSnackbarMessage!,
            kind: ArxaKitNotificationKind.error,
            title: config.errorSnackbarTitle,
            variant: config.errorSnackbarType,
            duration:
                config.errorSnackbarDuration ?? const Duration(seconds: 3),
          );
          break;

        case ArxaKitNotificationType.dialog:
          arxaKitLocator<ArxaKitNotificationService>().alert(
            title: config.errorSnackbarTitle ?? 'Error',
            message: config.errorSnackbarMessage!,
          );
          break;

        case ArxaKitNotificationType.bottomSheet:
          arxaKitLocator<ArxaKitNotificationService>().notice(
            title: config.errorSnackbarTitle ?? 'Error',
            message: config.errorSnackbarMessage!,
          );
          break;

        case ArxaKitNotificationType.none:
          // Do nothing
          break;
      }
    } catch (e, s) {
      _errorService.warning(
        error: e,
        stackTrace: s,
        message: 'Failed to show error notification',
        widgetId: config.widgetId,
      );
    }
  }
}
