import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:appbox_kit_core/appbox_kit_locator.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_core/services/error/appbox_kit_error_service.dart';
import 'package:appbox_kit_ui_library/services/notifications/appbox_kit_notification_service.dart';
import 'package:appbox_kit_ui_library/utils/kit_action/appbox_kit_action_config.dart';
import 'package:appbox_kit_ui_library/utils/kit_action/appbox_kit_snackbar_type.dart';
import 'package:appbox_kit_ui_library/utils/kit_action/managers/appbox_kit_notification_manager.dart';

import '../widgets/appbox_kit_native_test_helpers.dart';

/// Integration test for the AppBoxKitAction → notification hop that was previously
/// only compile-checked: `AppBoxKitNotificationManager.showXSnackbar()` resolves
/// `AppBoxKitNotificationService` from the appBoxKitLocator, calls `.show(kind:)`, and (on
/// the Android tier) lands on `SnackbarService.showCustomSnackBar(variant:)`.
///
/// This is the hop rewired when the kit snackbar service was unified; it lives
/// across two units (AppBoxKitNotificationManager + AppBoxKitNotificationService) wired only
/// through the appBoxKitLocator, so it is exercised end-to-end here with a recording
/// SnackbarService stub. AppBoxKitNotificationManager's static appBoxKitLocator deps
/// (AppBoxKitErrorService / DialogService / BottomSheetService / Talker) are
/// registered as real no-op instances — they're resolved at class-load but
/// never invoked on the snackbar path.
class _RecordingSnackbarService extends SnackbarService {
  int calls = 0;
  String? lastMessage;
  Object? lastVariant;

  @override
  Future<dynamic>? showCustomSnackBar({
    required String message,
    TextStyle? messageTextStyle,
    required dynamic variant,
    String? title,
    TextStyle? titleTextStyle,
    String? mainButtonTitle,
    ButtonStyle? mainButtonStyle,
    void Function()? onMainButtonTapped,
    Function? onTap,
    Duration? duration,
  }) {
    calls++;
    lastMessage = message;
    lastVariant = variant;
    return null;
  }
}

void main() {
  late _RecordingSnackbarService snackbar;

  setUp(() {
    appBoxKitLocator
      ..registerLazySingleton(() => Talker())
      ..registerLazySingleton(() => AppBoxKitErrorService())
      ..registerLazySingleton(() => DialogService())
      ..registerLazySingleton(() => BottomSheetService())
      ..registerLazySingleton(() => AppBoxKitNotificationService());
    snackbar = _RecordingSnackbarService();
    appBoxKitLocator.registerSingleton<SnackbarService>(snackbar);
    // Android tier so .show() routes to the snackbar tier (the stub). This is
    // the path where the hop is observable; the iOS-CNToast tier is covered in
    // kit_notification_service_test.dart.
    AppBoxKitPlatform.override =
        const AppBoxKitPlatformOverride(isAndroid: true);
  });

  tearDown(() {
    AppBoxKitPlatform.reset();
    appBoxKitLocator.reset();
  });

  AppBoxKitActionConfig<String> configWith(String widgetId) =>
      AppBoxKitActionConfig<String>(operation: () => 'ok', widgetId: widgetId);

  testWidgets(
      'kit.ui-library.action-notifications — loading notification: AppBoxKitNotificationManager → AppBoxKitNotificationService → SnackbarService',
      (tester) async {
    await tester.pumpWidget(host(const SizedBox.shrink()));
    final config = configWith('kit_action_notif_loading')
      ..loadingSnackbarMessage = 'loading…';

    AppBoxKitNotificationManager<String>(config).showLoadingSnackbar();

    expect(snackbar.calls, 1, reason: 'loading must reach the snackbar tier');
    expect(snackbar.lastMessage, 'loading…');
    expect(
      snackbar.lastVariant,
      AppBoxKitSnackbarType.appBoxKitAutoProcessInfo,
      reason: 'loading kind=info maps to the info variant',
    );
  });

  testWidgets(
      'kit.ui-library.action-notifications — success notification: AppBoxKitNotificationManager → AppBoxKitNotificationService → SnackbarService',
      (tester) async {
    await tester.pumpWidget(host(const SizedBox.shrink()));
    final config = configWith('kit_action_notif_success')
      ..successSnackbarMessage = 'done';

    AppBoxKitNotificationManager<String>(config).showSuccessSnackbar();

    expect(snackbar.calls, 1);
    expect(snackbar.lastMessage, 'done');
    expect(snackbar.lastVariant,
        AppBoxKitSnackbarType.appBoxKitAutoProcessSuccess);
  });

  testWidgets(
      'kit.ui-library.action-notifications — error notification: AppBoxKitNotificationManager → AppBoxKitNotificationService → SnackbarService',
      (tester) async {
    await tester.pumpWidget(host(const SizedBox.shrink()));
    final config = configWith('kit_action_notif_error')
      ..errorSnackbarMessage = 'failed';

    AppBoxKitNotificationManager<String>(config).showErrorSnackbar();

    expect(snackbar.calls, 1);
    expect(snackbar.lastMessage, 'failed');
    expect(
        snackbar.lastVariant, AppBoxKitSnackbarType.appBoxKitAutoProcessError);
  });

  testWidgets(
      'kit.ui-library.action-notifications — host-enum variant override flows through unchanged',
      (tester) async {
    // AppBoxKitActionConfig's *SnackbarType is dynamic — a host may pass its own enum
    // variant. The service must forward it verbatim on the snackbar tier
    // (mapped only when null).
    await tester.pumpWidget(host(const SizedBox.shrink()));
    final config = configWith('kit_action_notif_override')
      ..successSnackbarMessage = 'done'
      ..successSnackbarType = AppBoxKitSnackbarType.appBoxKitAutoProcessWarning;

    AppBoxKitNotificationManager<String>(config).showSuccessSnackbar();

    expect(
      snackbar.lastVariant,
      AppBoxKitSnackbarType.appBoxKitAutoProcessWarning,
      reason: 'explicit variant overrides the kind-derived default',
    );
  });
}
