import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:appbox_kit_core/kit_locator.dart';
import 'package:appbox_kit_core/platform/kit_platform.dart';
import 'package:appbox_kit_core/services/error/kit_error_service.dart';
import 'package:ui_library/services/notifications/kit_notification_service.dart';
import 'package:ui_library/utils/kit_action/kit_action_config.dart';
import 'package:ui_library/utils/kit_action/kit_snackbar_type.dart';
import 'package:ui_library/utils/kit_action/managers/notification_manager.dart';

import '../widgets/native_test_helpers.dart';

/// Integration test for the KitAction → notification hop that was previously
/// only compile-checked: `NotificationManager.showXSnackbar()` resolves
/// `KitNotificationService` from the locator, calls `.show(kind:)`, and (on
/// the Android tier) lands on `SnackbarService.showCustomSnackBar(variant:)`.
///
/// This is the hop rewired when the kit snackbar service was unified; it lives
/// across two units (NotificationManager + KitNotificationService) wired only
/// through the locator, so it is exercised end-to-end here with a recording
/// SnackbarService stub. NotificationManager's static locator deps
/// (KitErrorService / DialogService / BottomSheetService / Talker) are
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
    locator
      ..registerLazySingleton(() => Talker())
      ..registerLazySingleton(() => KitErrorService())
      ..registerLazySingleton(() => DialogService())
      ..registerLazySingleton(() => BottomSheetService())
      ..registerLazySingleton(() => KitNotificationService());
    snackbar = _RecordingSnackbarService();
    locator.registerSingleton<SnackbarService>(snackbar);
    // Android tier so .show() routes to the snackbar tier (the stub). This is
    // the path where the hop is observable; the iOS-CNToast tier is covered in
    // kit_notification_service_test.dart.
    KitPlatform.override = const KitPlatformOverride(isAndroid: true);
  });

  tearDown(() {
    KitPlatform.reset();
    locator.reset();
  });

  KitActionConfig<String> configWith(String widgetId) =>
      KitActionConfig<String>(operation: () => 'ok', widgetId: widgetId);

  testWidgets(
      'loading notification: NotificationManager → KitNotificationService → SnackbarService',
      (tester) async {
    await tester.pumpWidget(host(const SizedBox.shrink()));
    final config = configWith('kit_action_notif_loading')
      ..loadingSnackbarMessage = 'loading…';

    NotificationManager<String>(config).showLoadingSnackbar();

    expect(snackbar.calls, 1, reason: 'loading must reach the snackbar tier');
    expect(snackbar.lastMessage, 'loading…');
    expect(
      snackbar.lastVariant,
      KitSnackbarType.kitAutoProcessInfo,
      reason: 'loading kind=info maps to the info variant',
    );
  });

  testWidgets(
      'success notification: NotificationManager → KitNotificationService → SnackbarService',
      (tester) async {
    await tester.pumpWidget(host(const SizedBox.shrink()));
    final config = configWith('kit_action_notif_success')
      ..successSnackbarMessage = 'done';

    NotificationManager<String>(config).showSuccessSnackbar();

    expect(snackbar.calls, 1);
    expect(snackbar.lastMessage, 'done');
    expect(snackbar.lastVariant, KitSnackbarType.kitAutoProcessSuccess);
  });

  testWidgets(
      'error notification: NotificationManager → KitNotificationService → SnackbarService',
      (tester) async {
    await tester.pumpWidget(host(const SizedBox.shrink()));
    final config = configWith('kit_action_notif_error')
      ..errorSnackbarMessage = 'failed';

    NotificationManager<String>(config).showErrorSnackbar();

    expect(snackbar.calls, 1);
    expect(snackbar.lastMessage, 'failed');
    expect(snackbar.lastVariant, KitSnackbarType.kitAutoProcessError);
  });

  testWidgets('host-enum variant override flows through unchanged',
      (tester) async {
    // KitActionConfig's *SnackbarType is dynamic — a host may pass its own enum
    // variant. The service must forward it verbatim on the snackbar tier
    // (mapped only when null).
    await tester.pumpWidget(host(const SizedBox.shrink()));
    final config = configWith('kit_action_notif_override')
      ..successSnackbarMessage = 'done'
      ..successSnackbarType = KitSnackbarType.kitAutoProcessWarning;

    NotificationManager<String>(config).showSuccessSnackbar();

    expect(
      snackbar.lastVariant,
      KitSnackbarType.kitAutoProcessWarning,
      reason: 'explicit variant overrides the kind-derived default',
    );
  });
}
