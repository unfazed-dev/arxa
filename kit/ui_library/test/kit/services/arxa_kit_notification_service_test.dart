import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNGlassEffect, LiquidGlassContainer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:arxa_kit_ui_library/services/notifications/arxa_kit_notification_service.dart';
import 'package:arxa_kit_ui_library/utils/kit_action/arxa_kit_snackbar_type.dart';

import '../widgets/arxa_kit_native_test_helpers.dart';

/// ArxaKitNotificationService tests.
///
/// The service is a thin router with side effects, so it is tested by
/// branch-taken assertions rather than painting:
/// - **Android tier** + **iOS action-fallback tier** both land on the host
///   [SnackbarService]; a recording stub is registered in [arxaKitLocator] and we
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
  late ArxaKitNotificationService service;

  setUp(() => service = ArxaKitNotificationService());

  tearDown(() {
    ArxaKitPlatform.reset();
    arxaKitLocator.reset();
  });

  testWidgets(
      'kit.ui-library.notification-service — Android tier → SnackbarService (mapped variant + forwarded duration)',
      (tester) async {
    final svc = _RecordingSnackbarService();
    arxaKitLocator.registerSingleton<SnackbarService>(svc);
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'saved',
      kind: ArxaKitNotificationKind.success,
      duration: const Duration(seconds: 2),
    );

    expect(svc.calls, 1, reason: 'Android tier must invoke SnackbarService');
    expect(svc.lastMessage, 'saved');
    expect(
      svc.lastVariant,
      ArxaKitSnackbarType.arxaKitAutoProcessSuccess,
      reason: 'ArxaKitNotificationKind.success maps to the success variant',
    );
    expect(svc.lastDuration, const Duration(seconds: 2));
    expect(svc.lastActionLabel, isNull, reason: 'no action passed');
  });

  testWidgets(
      'kit.ui-library.notification-service — iOS/desktop tier, no action → CNToast (SnackbarService NOT invoked)',
      (tester) async {
    // The macOS test host has Platform.isAndroid == false, so
    // supportsComposeM3E is false and the CNToast tier is taken with no
    // override. This is the de-mix: a transient iOS notification never touches
    // the Material SnackbarService.
    final svc = _RecordingSnackbarService();
    arxaKitLocator.registerSingleton<SnackbarService>(svc);

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
      'kit.ui-library.notification-service — iOS/desktop tier: warning + center, no action → CNToast (not snackbar)',
      (tester) async {
    // Neither the warning kind nor the center position may promote iOS to the
    // snackbar tier — only actionLabel / Android do. Warning now routes to
    // CNToast.warning (yellow/orange tint), not info-blue.
    final svc = _RecordingSnackbarService();
    arxaKitLocator.registerSingleton<SnackbarService>(svc);

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'careful',
      kind: ArxaKitNotificationKind.warning,
      position: ArxaKitToastPosition.center,
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

  testWidgets(
      'kit.ui-library.notification-service — iOS/desktop tier, with actionLabel → SnackbarService fallback',
      (tester) async {
    final svc = _RecordingSnackbarService();
    arxaKitLocator.registerSingleton<SnackbarService>(svc);
    // Still non-Android (macOS host): proves actionLabel ALONE promotes to the
    // snackbar tier off-Android, because CNToast cannot host an action button.

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'deleted',
      kind: ArxaKitNotificationKind.error,
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
    expect(svc.lastVariant, ArxaKitSnackbarType.arxaKitAutoProcessError);
    expect(svc.lastActionLabel, 'Undo');
    expect(svc.lastAction, isNotNull);
  });

  testWidgets(
      'kit.ui-library.notification-service — variant override is honored on the snackbar tier',
      (tester) async {
    final svc = _RecordingSnackbarService();
    arxaKitLocator.registerSingleton<SnackbarService>(svc);
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'x',
      kind: ArxaKitNotificationKind.info,
      variant: ArxaKitSnackbarType.arxaKitAutoProcessWarning,
    );

    expect(
      svc.lastVariant,
      ArxaKitSnackbarType.arxaKitAutoProcessWarning,
      reason: 'explicit variant overrides the kind-derived default',
    );
  });

  testWidgets(
      'kit.ui-library.notification-service — Android tier, position center → kit center pill (SnackbarService NOT invoked)',
      (tester) async {
    final svc = _RecordingSnackbarService();
    arxaKitLocator.registerSingleton<SnackbarService>(svc);
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'saved',
      kind: ArxaKitNotificationKind.success,
      position: ArxaKitToastPosition.center,
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
    final pill = find.byKey(const Key('arxaKitCenterToastPill'));
    expect(pill, findsOneWidget);
    expect(find.text('saved'), findsOneWidget);

    // The pill rides a PLAIN compositing anchor (same mechanism as the input
    // bar's opaque base): without it, in-scroll native glass renders OVER the
    // toast because the view slicer only hoists Flutter ops that intersect a
    // platform-view rect. Pure Dart here: the vendored container only bridges
    // when a UiKitView materializes.
    expect(
      find.ancestor(of: pill, matching: find.byType(LiquidGlassContainer)),
      findsOneWidget,
      reason: 'center pill must mount the plain slicer anchor — without it '
          'scrolling native glass covers the toast',
    );

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

  testWidgets(
      'kit.ui-library.notification-service — center pill elevation rides the anchor config, never a pill-painted BoxShadow',
      (tester) async {
    // 2026-08-15 device clip: the pill's own BoxShadow spilled past the
    // anchor platform view's rect and past the pill's layer bounds; the view
    // slicer + the fade's opacity surface clipped it at the pill's
    // RECTANGULAR bounding box — a faint hard-edged rectangle where the soft
    // shadow should be (and in worse scenes the shadow vanished outright).
    // Elevation must be declared on the anchor's LiquidGlassConfig (native
    // CALayer shadow on the glass tier, shape-matched ShapeDecoration on the
    // fallback tier) and the pill decoration must stay shadow-free.
    final svc = _RecordingSnackbarService();
    arxaKitLocator.registerSingleton<SnackbarService>(svc);
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'elevation',
      kind: ArxaKitNotificationKind.info,
      position: ArxaKitToastPosition.center,
      duration: const Duration(seconds: 2),
      context: tester.element(find.byType(Scaffold)),
    );
    await tester.pump();

    final pill = find.byKey(const Key('arxaKitCenterToastPill'));
    expect(pill, findsOneWidget);

    // The anchor carries the elevation spec.
    final anchor = tester.widget<LiquidGlassContainer>(
      find.ancestor(of: pill, matching: find.byType(LiquidGlassContainer)),
    );
    expect(anchor.config.effect, CNGlassEffect.plain);
    final shadow = anchor.config.shadow;
    expect(shadow, isNotNull,
        reason: 'elevation is declared on the anchor config');
    expect(shadow!.radius, 16.0);
    expect(shadow.opacity, 0.15);
    expect(shadow.offset, const Offset(0, 6));

    // The pill paints no shadow of its own — the artifact's cause.
    final decoration =
        tester.widget<Container>(pill).decoration as BoxDecoration;
    expect(decoration.boxShadow, isNull,
        reason: 'a pill-painted BoxShadow spills past the anchor rect and '
            'renders as a hard-edged rectangle on the glass tier');

    // The fallback tier still paints the elevation (shape-matched shadow
    // under the anchor) — pre-glass devices keep the same look.
    final shapeShadow = find.descendant(
      of: find.byType(LiquidGlassContainer),
      matching: find.byWidgetPredicate((w) {
        if (w is! DecoratedBox) return false;
        final d = w.decoration;
        return d is ShapeDecoration &&
            d.shadows != null &&
            d.shadows!.isNotEmpty;
      }),
    );
    expect(shapeShadow, findsOneWidget,
        reason: 'the fallback tier must keep painting the elevation shadow');

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
      'kit.ui-library.notification-service — iOS action tier, position center → center pill hosts the action',
      (tester) async {
    final svc = _RecordingSnackbarService();
    arxaKitLocator.registerSingleton<SnackbarService>(svc);
    // Non-Android host: actionLabel alone would force the snackbar fallback;
    // with center the kit pill takes over AND still hosts the action.
    var tapped = false;

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'deleted',
      kind: ArxaKitNotificationKind.error,
      position: ArxaKitToastPosition.center,
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
      'kit.ui-library.notification-service — Android tier, position bottom → SnackbarService (unchanged behavior)',
      (tester) async {
    final svc = _RecordingSnackbarService();
    arxaKitLocator.registerSingleton<SnackbarService>(svc);
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'saved',
      position: ArxaKitToastPosition.bottom,
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
      'kit.ui-library.notification-service — iOS/desktop tier: center maps to CNToastPosition.center (paints at screen center)',
      (tester) async {
    final svc = _RecordingSnackbarService();
    arxaKitLocator.registerSingleton<SnackbarService>(svc);

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await service.show(
      'mid',
      position: ArxaKitToastPosition.center,
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

  testWidgets(
      'kit.ui-library.notification-service — toast tiers mount in the ROOT overlay, not a nested navigator\'s',
      (tester) async {
    // Regression: a context inside a nested Navigator (tab shell, sheet)
    // resolves a NEARER Overlay whose entries paint under anything the shell
    // stacks above that navigator — a scrolling surface could cover the toast.
    // Both CNToast call sites and the kit center pill must pass
    // `rootOverlay: true`. Asserted structurally (which OverlayState hosts the
    // entry), not by paint order, so the test pins the exact mechanism.
    final svc = _RecordingSnackbarService();
    arxaKitLocator.registerSingleton<SnackbarService>(svc);
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);

    late BuildContext innerContext;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Navigator(
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (context) => Builder(builder: (context) {
              innerContext = context;
              return const SizedBox.shrink();
            }),
          ),
        ),
      ),
    ));

    // Fixture is real only if the nested navigator supplies a nearer overlay.
    final nearest = Overlay.of(innerContext);
    final root = Overlay.of(innerContext, rootOverlay: true);
    expect(nearest, isNot(same(root)),
        reason: 'nested Navigator must own its own Overlay for this test '
            'to distinguish the two insertion targets');

    await service.show(
      'saved',
      position: ArxaKitToastPosition.center,
      duration: const Duration(seconds: 2),
      context: innerContext,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final pill = find.byKey(const Key('arxaKitCenterToastPill'));
    expect(pill, findsOneWidget);
    final hostOverlay =
        tester.element(pill).findAncestorStateOfType<OverlayState>();
    expect(hostOverlay, same(root),
        reason: 'the center pill must outrank every surface in the app — '
            'inserting into the nested overlay lets shell chrome cover it');

    // Drain the auto-dismiss Timer before teardown.
    await tester.pump(const Duration(seconds: 2));
    expect(pill, findsNothing);
  });
}
