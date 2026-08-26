import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:arxa_kit_core/services/error/arxa_kit_error_service.dart';
import 'package:arxa_kit_ui_library/services/notifications/arxa_kit_notification_service.dart';
import 'package:arxa_kit_ui_library/utils/kit_action/arxa_kit_action_config.dart';
import 'package:arxa_kit_ui_library/utils/kit_action/arxa_kit_snackbar_type.dart';
import 'package:arxa_kit_ui_library/utils/kit_action/managers/arxa_kit_notification_manager.dart';

import '../widgets/arxa_kit_native_test_helpers.dart';

/// Integration test for the ArxaKitAction → notification hop that was previously
/// only compile-checked: `ArxaKitNotificationManager.showXSnackbar()` resolves
/// `ArxaKitNotificationService` from the arxaKitLocator, calls `.show(kind:)`, and (on
/// the Android tier) lands on `SnackbarService.showCustomSnackBar(variant:)`.
///
/// This is the hop rewired when the kit snackbar service was unified; it lives
/// across two units (ArxaKitNotificationManager + ArxaKitNotificationService) wired only
/// through the arxaKitLocator, so it is exercised end-to-end here with a recording
/// SnackbarService stub. ArxaKitNotificationManager's static arxaKitLocator deps
/// (ArxaKitErrorService / DialogService / BottomSheetService / Talker) are
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
    arxaKitLocator
      ..registerLazySingleton(() => Talker())
      ..registerLazySingleton(() => ArxaKitErrorService())
      ..registerLazySingleton(() => DialogService())
      ..registerLazySingleton(() => BottomSheetService())
      ..registerLazySingleton(() => ArxaKitNotificationService());
    snackbar = _RecordingSnackbarService();
    arxaKitLocator.registerSingleton<SnackbarService>(snackbar);
    // Android tier so .show() routes to the snackbar tier (the stub). This is
    // the path where the hop is observable; the iOS-CNToast tier is covered in
    // kit_notification_service_test.dart.
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
  });

  tearDown(() {
    ArxaKitPlatform.reset();
    arxaKitLocator.reset();
  });

  ArxaKitActionConfig<String> configWith(String widgetId) =>
      ArxaKitActionConfig<String>(operation: () => 'ok', widgetId: widgetId);

  testWidgets(
      'kit.ui-library.action-notifications — loading notification: ArxaKitNotificationManager → ArxaKitNotificationService → SnackbarService',
      (tester) async {
    await tester.pumpWidget(host(const SizedBox.shrink()));
    final config = configWith('kit_action_notif_loading')
      ..loadingSnackbarMessage = 'loading…';

    ArxaKitNotificationManager<String>(config).showLoadingSnackbar();

    expect(snackbar.calls, 1, reason: 'loading must reach the snackbar tier');
    expect(snackbar.lastMessage, 'loading…');
    expect(
      snackbar.lastVariant,
      ArxaKitSnackbarType.arxaKitAutoProcessInfo,
      reason: 'loading kind=info maps to the info variant',
    );
  });

  testWidgets(
      'kit.ui-library.action-notifications — success notification: ArxaKitNotificationManager → ArxaKitNotificationService → SnackbarService',
      (tester) async {
    await tester.pumpWidget(host(const SizedBox.shrink()));
    final config = configWith('kit_action_notif_success')
      ..successSnackbarMessage = 'done';

    ArxaKitNotificationManager<String>(config).showSuccessSnackbar();

    expect(snackbar.calls, 1);
    expect(snackbar.lastMessage, 'done');
    expect(snackbar.lastVariant,
        ArxaKitSnackbarType.arxaKitAutoProcessSuccess);
  });

  testWidgets(
      'kit.ui-library.action-notifications — error notification: ArxaKitNotificationManager → ArxaKitNotificationService → SnackbarService',
      (tester) async {
    await tester.pumpWidget(host(const SizedBox.shrink()));
    final config = configWith('kit_action_notif_error')
      ..errorSnackbarMessage = 'failed';

    ArxaKitNotificationManager<String>(config).showErrorSnackbar();

    expect(snackbar.calls, 1);
    expect(snackbar.lastMessage, 'failed');
    expect(
        snackbar.lastVariant, ArxaKitSnackbarType.arxaKitAutoProcessError);
  });

  testWidgets(
      'kit.ui-library.action-notifications — host-enum variant override flows through unchanged',
      (tester) async {
    // ArxaKitActionConfig's *SnackbarType is dynamic — a host may pass its own enum
    // variant. The service must forward it verbatim on the snackbar tier
    // (mapped only when null).
    await tester.pumpWidget(host(const SizedBox.shrink()));
    final config = configWith('kit_action_notif_override')
      ..successSnackbarMessage = 'done'
      ..successSnackbarType = ArxaKitSnackbarType.arxaKitAutoProcessWarning;

    ArxaKitNotificationManager<String>(config).showSuccessSnackbar();

    expect(
      snackbar.lastVariant,
      ArxaKitSnackbarType.arxaKitAutoProcessWarning,
      reason: 'explicit variant overrides the kind-derived default',
    );
  });
}
