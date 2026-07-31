import 'package:appbox_kit_core/kit_locator.dart';
import 'package:appbox_kit_core/services/error/kit_error_service.dart';
import '../../../services/notifications/kit_notification_service.dart';
import '../kit_action_config.dart';
import '../notification_type.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// KitAction v2.0 - NotificationManager
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 4.2: Component Responsibilities - NotificationManager (lines 344-351)
//    - Section 5.2: Notifications & Types (lines 769-927)
//
// Manages user notifications with multiple display types (NEW in v2.0).
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages notifications for operations (snackbars, dialogs, bottom sheets)
/// Handles loading, success, and error notifications based on configured type
class NotificationManager<T> {
  final KitActionConfig<T> config;
  static final _errorService = locator<KitErrorService>();
  static final _dialogService = locator<DialogService>();
  static final _bottomSheetService = locator<BottomSheetService>();
  static final _talker = locator<Talker>();

  NotificationManager(this.config);

  /// Show loading notification based on configured type
  void showLoadingSnackbar() {
    if (config.loadingSnackbarMessage == null) return;

    if (config.debugMode) {
      _talker.debug(
        '[KitAction] 🔔 NotificationManager: Showing loading notification (${config.loadingNotificationType.name}) for ${config.widgetId}',
      );
    }

    try {
      switch (config.loadingNotificationType) {
        case NotificationType.snackbar:
          locator<KitNotificationService>().show(
            config.loadingSnackbarMessage!,
            kind: KitNotificationKind.info,
            title: config.loadingSnackbarTitle,
            variant: config.loadingSnackbarType,
            duration:
                config.loadingSnackbarDuration ?? const Duration(seconds: 2),
          );
          break;

        case NotificationType.dialog:
          _dialogService.showDialog(
            title: config.loadingSnackbarTitle ?? 'Loading',
            description: config.loadingSnackbarMessage!,
            barrierDismissible: false,
          );
          break;

        case NotificationType.bottomSheet:
          _bottomSheetService.showBottomSheet(
            title: config.loadingSnackbarTitle ?? 'Loading',
            description: config.loadingSnackbarMessage!,
          );
          break;

        case NotificationType.none:
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
        '[KitAction] ✅ NotificationManager: Showing success notification (${config.successNotificationType.name}) for ${config.widgetId}',
      );
    }

    try {
      switch (config.successNotificationType) {
        case NotificationType.snackbar:
          locator<KitNotificationService>().show(
            config.successSnackbarMessage!,
            kind: KitNotificationKind.success,
            title: config.successSnackbarTitle,
            variant: config.successSnackbarType,
            duration:
                config.successSnackbarDuration ?? const Duration(seconds: 3),
          );
          break;

        case NotificationType.dialog:
          _dialogService.showDialog(
            title: config.successSnackbarTitle ?? 'Success',
            description: config.successSnackbarMessage!,
            buttonTitle: 'OK',
          );
          break;

        case NotificationType.bottomSheet:
          _bottomSheetService.showBottomSheet(
            title: config.successSnackbarTitle ?? 'Success',
            description: config.successSnackbarMessage!,
          );
          break;

        case NotificationType.none:
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
        '[KitAction] ⚠️ NotificationManager: Showing error notification (${config.errorNotificationType.name}) for ${config.widgetId}',
      );
    }

    try {
      switch (config.errorNotificationType) {
        case NotificationType.snackbar:
          locator<KitNotificationService>().show(
            config.errorSnackbarMessage!,
            kind: KitNotificationKind.error,
            title: config.errorSnackbarTitle,
            variant: config.errorSnackbarType,
            duration:
                config.errorSnackbarDuration ?? const Duration(seconds: 3),
          );
          break;

        case NotificationType.dialog:
          _dialogService.showDialog(
            title: config.errorSnackbarTitle ?? 'Error',
            description: config.errorSnackbarMessage!,
            buttonTitle: 'OK',
          );
          break;

        case NotificationType.bottomSheet:
          _bottomSheetService.showBottomSheet(
            title: config.errorSnackbarTitle ?? 'Error',
            description: config.errorSnackbarMessage!,
          );
          break;

        case NotificationType.none:
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
