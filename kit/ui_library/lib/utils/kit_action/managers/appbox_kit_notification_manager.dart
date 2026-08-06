import 'package:appbox_kit_core/appbox_kit_locator.dart';
import 'package:appbox_kit_core/services/error/appbox_kit_error_service.dart';
import '../../../services/notifications/appbox_kit_notification_service.dart';
import '../appbox_kit_action_config.dart';
import '../appbox_kit_notification_type.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AppBoxKitAction v2.0 - AppBoxKitNotificationManager
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 4.2: Component Responsibilities - AppBoxKitNotificationManager (lines 344-351)
//    - Section 5.2: Notifications & Types (lines 769-927)
//
// Manages user notifications with multiple display types (NEW in v2.0).
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages notifications for operations (snackbars, dialogs, bottom sheets)
/// Handles loading, success, and error notifications based on configured type
class AppBoxKitNotificationManager<T> {
  final AppBoxKitActionConfig<T> config;
  static final _errorService = appBoxKitLocator<AppBoxKitErrorService>();
  static final _dialogService = appBoxKitLocator<DialogService>();
  static final _bottomSheetService = appBoxKitLocator<BottomSheetService>();
  static final _talker = appBoxKitLocator<Talker>();

  AppBoxKitNotificationManager(this.config);

  /// Show loading notification based on configured type
  void showLoadingSnackbar() {
    if (config.loadingSnackbarMessage == null) return;

    if (config.debugMode) {
      _talker.debug(
        '[AppBoxKitAction] 🔔 AppBoxKitNotificationManager: Showing loading notification (${config.loadingNotificationType.name}) for ${config.widgetId}',
      );
    }

    try {
      switch (config.loadingNotificationType) {
        case AppBoxKitNotificationType.snackbar:
          appBoxKitLocator<AppBoxKitNotificationService>().show(
            config.loadingSnackbarMessage!,
            kind: AppBoxKitNotificationKind.info,
            title: config.loadingSnackbarTitle,
            variant: config.loadingSnackbarType,
            duration:
                config.loadingSnackbarDuration ?? const Duration(seconds: 2),
          );
          break;

        case AppBoxKitNotificationType.dialog:
          _dialogService.showDialog(
            title: config.loadingSnackbarTitle ?? 'Loading',
            description: config.loadingSnackbarMessage!,
            barrierDismissible: false,
          );
          break;

        case AppBoxKitNotificationType.bottomSheet:
          _bottomSheetService.showBottomSheet(
            title: config.loadingSnackbarTitle ?? 'Loading',
            description: config.loadingSnackbarMessage!,
          );
          break;

        case AppBoxKitNotificationType.none:
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
        '[AppBoxKitAction] ✅ AppBoxKitNotificationManager: Showing success notification (${config.successNotificationType.name}) for ${config.widgetId}',
      );
    }

    try {
      switch (config.successNotificationType) {
        case AppBoxKitNotificationType.snackbar:
          appBoxKitLocator<AppBoxKitNotificationService>().show(
            config.successSnackbarMessage!,
            kind: AppBoxKitNotificationKind.success,
            title: config.successSnackbarTitle,
            variant: config.successSnackbarType,
            duration:
                config.successSnackbarDuration ?? const Duration(seconds: 3),
          );
          break;

        case AppBoxKitNotificationType.dialog:
          _dialogService.showDialog(
            title: config.successSnackbarTitle ?? 'Success',
            description: config.successSnackbarMessage!,
            buttonTitle: 'OK',
          );
          break;

        case AppBoxKitNotificationType.bottomSheet:
          _bottomSheetService.showBottomSheet(
            title: config.successSnackbarTitle ?? 'Success',
            description: config.successSnackbarMessage!,
          );
          break;

        case AppBoxKitNotificationType.none:
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
        '[AppBoxKitAction] ⚠️ AppBoxKitNotificationManager: Showing error notification (${config.errorNotificationType.name}) for ${config.widgetId}',
      );
    }

    try {
      switch (config.errorNotificationType) {
        case AppBoxKitNotificationType.snackbar:
          appBoxKitLocator<AppBoxKitNotificationService>().show(
            config.errorSnackbarMessage!,
            kind: AppBoxKitNotificationKind.error,
            title: config.errorSnackbarTitle,
            variant: config.errorSnackbarType,
            duration:
                config.errorSnackbarDuration ?? const Duration(seconds: 3),
          );
          break;

        case AppBoxKitNotificationType.dialog:
          _dialogService.showDialog(
            title: config.errorSnackbarTitle ?? 'Error',
            description: config.errorSnackbarMessage!,
            buttonTitle: 'OK',
          );
          break;

        case AppBoxKitNotificationType.bottomSheet:
          _bottomSheetService.showBottomSheet(
            title: config.errorSnackbarTitle ?? 'Error',
            description: config.errorSnackbarMessage!,
          );
          break;

        case AppBoxKitNotificationType.none:
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
