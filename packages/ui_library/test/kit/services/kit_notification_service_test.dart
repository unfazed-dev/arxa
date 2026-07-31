import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:appbox_kit_core/kit_locator.dart';
import 'package:appbox_kit_core/platform/kit_platform.dart';
import 'package:ui_library/services/notifications/kit_notification_service.dart';
import 'package:ui_library/utils/kit_action/kit_snackbar_type.dart';

import '../widgets/native_test_helpers.dart';

/// KitNotificationService tests.
///
/// The service is a thin router with side effects, so it is tested by
/// branch-taken assertions rather than painting:
/// - **Android tier** + **iOS action-fallback tier** both land on the host
///   [SnackbarService]; a recording stub is registered in [locator] and we
///   assert the call + mapped variant + forwarded fields.
/// - **Snackbar tier + `position: center`** routes to the kit-owned center
///   floating pill (an Overlay surface; the SnackbarService is NOT invoked)
///   — asserted by geometry (pill center == screen center) and by the action
///   button the pill still hosts on the iOS fallback tier.
/// - **iOS / desktop tier, no action** routes to [CNToast]; we assert the
///   SnackbarService is NOT invoked — that is the de-mix contract (no snackbar
///   on iOS unless an action is required). CNToast itself is fire-and-forget
///   and paint-unasserted (same stance as the former toast test).
class _RecordingSnackbarService extends SnackbarService {
  int calls = 0;
  String? lastMessage;
  Object? lastVariant;
  Duration? lastDuration;
  String? lastActionLabel;
  VoidCallback? lastAction;

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
    lastDuration = duration;
    lastActionLabel = mainButtonTitle;
    lastAction = onMainButtonTapped;
    return null;
  }
}

void main() {
  late KitNotificationService service;

  setUp(() => service = KitNotificationService());

  tearDown(() {
    KitPlatform.reset();
    locator.reset();
  });

  testWidgets(
      'Android tier → SnackbarService (mapped variant + forwarded duration)',
      (tester) async {
    final svc = _RecordingSnackbarService();
    locator.registerSingleton<SnackbarService>(svc);
    KitPlatform.override = const KitPlatformOverride(isAndroid: true);

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'saved',
      kind: KitNotificationKind.success,
      duration: const Duration(seconds: 2),
    );

    expect(svc.calls, 1, reason: 'Android tier must invoke SnackbarService');
    expect(svc.lastMessage, 'saved');
    expect(
      svc.lastVariant,
      KitSnackbarType.kitAutoProcessSuccess,
      reason: 'KitNotificationKind.success maps to the success variant',
    );
    expect(svc.lastDuration, const Duration(seconds: 2));
    expect(svc.lastActionLabel, isNull, reason: 'no action passed');
  });

  testWidgets(
      'iOS/desktop tier, no action → CNToast (SnackbarService NOT invoked)',
      (tester) async {
    // The macOS test host has Platform.isAndroid == false, so
    // supportsComposeM3E is false and the CNToast tier is taken with no
    // override. This is the de-mix: a transient iOS notification never touches
    // the Material SnackbarService.
    final svc = _RecordingSnackbarService();
    locator.registerSingleton<SnackbarService>(svc);

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'hi',
      context: tester.element(find.byType(Scaffold)),
    );
    await tester.pump(); // mount the CNToast overlay entry
    // CNToast schedules a real auto-dismiss Timer (medium = 3.5s; see
    // cupertino_native_better toast.dart). Pump past it so no Timer is left
    // pending at teardown. The de-mix assertion itself is svc.calls == 0.
    await tester.pump(const Duration(seconds: 4));

    expect(
      svc.calls,
      0,
      reason: 'iOS no-action must route to CNToast, never the SnackbarService',
    );
  });

  testWidgets(
      'iOS/desktop tier: warning + center, no action → CNToast (not snackbar)',
      (tester) async {
    // Neither the warning kind nor the center position may promote iOS to the
    // snackbar tier — only actionLabel / Android do. Warning now routes to
    // CNToast.warning (yellow/orange tint), not info-blue.
    final svc = _RecordingSnackbarService();
    locator.registerSingleton<SnackbarService>(svc);

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'careful',
      kind: KitNotificationKind.warning,
      position: KitToastPosition.center,
      context: tester.element(find.byType(Scaffold)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(
      svc.calls,
      0,
      reason: 'warning/center must stay on the CNToast tier',
    );
  });

  testWidgets('iOS/desktop tier, with actionLabel → SnackbarService fallback',
      (tester) async {
    final svc = _RecordingSnackbarService();
    locator.registerSingleton<SnackbarService>(svc);
    // Still non-Android (macOS host): proves actionLabel ALONE promotes to the
    // snackbar tier off-Android, because CNToast cannot host an action button.

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'deleted',
      kind: KitNotificationKind.error,
      context: tester.element(find.byType(Scaffold)),
      actionLabel: 'Undo',
      onAction: () {},
    );

    expect(
      svc.calls,
      1,
      reason: 'actionLabel forces the snackbar tier even on iOS',
    );
    expect(svc.lastMessage, 'deleted');
    expect(svc.lastVariant, KitSnackbarType.kitAutoProcessError);
    expect(svc.lastActionLabel, 'Undo');
    expect(svc.lastAction, isNotNull);
  });

  testWidgets('variant override is honored on the snackbar tier',
      (tester) async {
    final svc = _RecordingSnackbarService();
    locator.registerSingleton<SnackbarService>(svc);
    KitPlatform.override = const KitPlatformOverride(isAndroid: true);

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'x',
      kind: KitNotificationKind.info,
      variant: KitSnackbarType.kitAutoProcessWarning,
    );

    expect(
      svc.lastVariant,
      KitSnackbarType.kitAutoProcessWarning,
      reason: 'explicit variant overrides the kind-derived default',
    );
  });

  testWidgets(
      'Android tier, position center → kit center pill (SnackbarService NOT invoked)',
      (tester) async {
    final svc = _RecordingSnackbarService();
    locator.registerSingleton<SnackbarService>(svc);
    KitPlatform.override = const KitPlatformOverride(isAndroid: true);

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'saved',
      kind: KitNotificationKind.success,
      position: KitToastPosition.center,
      duration: const Duration(seconds: 2),
      context: tester.element(find.byType(Scaffold)),
    );
    await tester.pump(); // mount the pill's overlay entry
    await tester.pump(const Duration(milliseconds: 300)); // finish entrance

    expect(
      svc.calls,
      0,
      reason: 'center on the snackbar tier renders the kit pill, '
          'never the GetX snackbar',
    );
    final pill = find.byKey(const Key('kitCenterToastPill'));
    expect(pill, findsOneWidget);
    expect(find.text('saved'), findsOneWidget);

    // M3-idiomatic floating pill: horizontally centered at screen center.
    final screen = tester.getSize(find.byType(Scaffold));
    final center = tester.getCenter(pill);
    expect(center.dx, moreOrLessEquals(screen.width / 2, epsilon: 1));
    expect(center.dy, moreOrLessEquals(screen.height / 2, epsilon: 1));

    // Auto-dismisses after the duration. Explicit pump, not pumpAndSettle:
    // with no scheduled frame the pill is idle, so only elapsing fake time
    // fires the dismiss Timer (which removes the entry directly).
    await tester.pump(const Duration(seconds: 2));
    expect(pill, findsNothing);
  });

  testWidgets('iOS action tier, position center → center pill hosts the action',
      (tester) async {
    final svc = _RecordingSnackbarService();
    locator.registerSingleton<SnackbarService>(svc);
    // Non-Android host: actionLabel alone would force the snackbar fallback;
    // with center the kit pill takes over AND still hosts the action.
    var tapped = false;

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'deleted',
      kind: KitNotificationKind.error,
      position: KitToastPosition.center,
      actionLabel: 'Undo',
      onAction: () => tapped = true,
      duration: const Duration(seconds: 5),
      context: tester.element(find.byType(Scaffold)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(svc.calls, 0, reason: 'center keeps iOS off the GetX snackbar');
    expect(find.text('deleted'), findsOneWidget);
    final action = find.text('Undo');
    expect(action, findsOneWidget, reason: 'the pill hosts the action button');

    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
    expect(find.text('deleted'), findsNothing,
        reason: 'tapping the action dismisses the pill');
  });

  testWidgets(
      'Android tier, position bottom → SnackbarService (unchanged behavior)',
      (tester) async {
    final svc = _RecordingSnackbarService();
    locator.registerSingleton<SnackbarService>(svc);
    KitPlatform.override = const KitPlatformOverride(isAndroid: true);

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'saved',
      position: KitToastPosition.bottom,
      duration: const Duration(seconds: 2),
    );

    expect(
      svc.calls,
      1,
      reason: 'bottom stays on the host SnackbarService (bottom-anchored)',
    );
    expect(svc.lastMessage, 'saved');
  });

  testWidgets(
      'iOS/desktop tier: center maps to CNToastPosition.center (paints at screen center)',
      (tester) async {
    final svc = _RecordingSnackbarService();
    locator.registerSingleton<SnackbarService>(svc);

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'mid',
      position: KitToastPosition.center,
      context: tester.element(find.byType(Scaffold)),
    );
    await tester.pump(); // mount the CNToast overlay entry
    await tester.pump(const Duration(milliseconds: 200)); // finish entrance

    expect(svc.calls, 0, reason: 'no action → stays on the CNToast tier');
    final message = find.text('mid');
    expect(message, findsOneWidget);
    final screen = tester.getSize(find.byType(Scaffold));
    final center = tester.getCenter(message);
    expect(
      center.dy,
      moreOrLessEquals(screen.height / 2, epsilon: 1),
      reason: 'CNToastPosition.center pins the toast at screen center',
    );
    expect(
      center.dx,
      moreOrLessEquals(screen.width / 2, epsilon: 40),
      reason: 'leading icon shifts only the text, not the capsule, off-center',
    );

    // Drain CNToast's auto-dismiss Timer (medium = 3.5s) before teardown.
    await tester.pump(const Duration(seconds: 4));
  });
}
