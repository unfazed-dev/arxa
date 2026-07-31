// Widget tests for the ADR 0011 components showcase surface — the demos
// themselves are proven in ui_library's per-component tests; these pin the
// showcase wiring (sections render, dialog/sheet/center-toast/drawer
// presentation paths fire from this surface).
//
// The whole file runs on the Android tier override (same pattern as the
// kit's own Android-tier tests): the dialog routes to the stock AlertDialog,
// the sheet to showModalBottomSheet, and the center toast to the kit-owned
// center pill — no platform views, so everything renders headless.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_components/showcase_components_view.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:ui_library/ui_library.dart';

import 'helpers.dart';

/// The Android toast tier renders through stacked_services' GetX snackbar,
/// which needs a GetMaterialApp the test harness doesn't have — stub it (same
/// pattern as ui_library's own notification-service tests) and record calls
/// so the feedback paths stay assertable.
class _StubSnackbarService extends SnackbarService {
  final shown = <String>[];

  @override
  Future<void>? showCustomSnackBar({
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
    shown.add(message);
    return null;
  }
}

void main() {
  late _StubSnackbarService snackbar;

  setUpAll(registerKitTestServices);
  tearDownAll(() => locator.reset());

  setUp(() {
    KitPlatform.override = const KitPlatformOverride(isAndroid: true);
    if (locator.isRegistered<SnackbarService>()) {
      locator.unregister<SnackbarService>();
    }
    snackbar = _StubSnackbarService();
    locator.registerSingleton<SnackbarService>(snackbar);
  });
  tearDown(KitPlatform.reset);

  Future<void> pumpView(WidgetTester tester) async {
    // Tall surface so the whole demo list is built and tappable — the default
    // 800×600 test view leaves the overlay buttons below the lazy ListView's
    // cache extent (finders match 0 widgets, taps miss).
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: ShowcaseComponentsView()));
    await tester.pumpAndSettle();
  }

  testWidgets('renders every demo section', (tester) async {
    await pumpView(tester);

    expect(find.byType(KitFrostedSurface), findsWidgets,
        reason: 'the explicit frosted content-tier card');
    expect(find.byType(KitChipCarousel), findsOneWidget);
    expect(find.byType(KitChip), findsNWidgets(10));
    expect(find.byType(KitListSection), findsOneWidget,
        reason: 'the settings group in the body (the drawer menu group only '
            'builds once the drawer first opens)');
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).drawer, isNotNull,
        reason: 'the glassPeek KitDrawer is configured on the Scaffold '
            '(its subtree only builds once opened)');
    expect(find.byType(KitNativeInputBar), findsOneWidget);
  });

  testWidgets('Show dialog presents the native dialog and pops on action',
      (tester) async {
    await pumpView(tester);

    await tester.tap(find.text('Show dialog'));
    await tester.pumpAndSettle();
    expect(find.text('Delete note?'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget,
        reason: 'the destructive action is stacked with primary/secondary');

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete note?'), findsNothing,
        reason: 'tapping an action pops the dialog');
    expect(snackbar.shown, contains('Dialog: deleted'),
        reason: 'the dialog resolves to the action value and the demo toasts '
            'the result');
  });

  testWidgets('Show frosted sheet presents kitShowNativeSheet', (tester) async {
    await pumpView(tester);

    await tester.tap(find.text('Show frosted sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Frosted sheet body'), findsOneWidget);

    await tester.tapAt(const Offset(20, 20)); // barrier dismiss
    await tester.pumpAndSettle();
    expect(find.text('Frosted sheet body'), findsNothing);
  });

  testWidgets('Show center toast fires the center pill', (tester) async {
    await pumpView(tester);

    await tester.tap(find.text('Show center toast'));
    await tester.pump(); // mount the pill's overlay entry
    expect(find.byKey(const Key('kitCenterToastPill')), findsOneWidget);
    expect(find.text('Centered'), findsOneWidget);

    // Auto-dismiss (3s default) — elapse fake time so no timer is pending.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kitCenterToastPill')), findsNothing);
  });

  testWidgets('drawer opens via the button and closes on scrim tap',
      (tester) async {
    await pumpView(tester);

    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
    expect(scaffold.isDrawerOpen, isFalse);

    await tester.tap(find.text('Open drawer'));
    await tester.pumpAndSettle();
    expect(scaffold.isDrawerOpen, isTrue,
        reason: 'Open drawer calls Scaffold.of(context).openDrawer()');
    expect(find.byType(KitDrawer), findsOneWidget,
        reason: 'the opened drawer builds the KitDrawer (glassPeek) subtree');
    expect(find.text('About'), findsOneWidget,
        reason: 'menu rows are KitListTiles inside a KitListSection');
    expect(find.byType(KitListSection), findsNWidgets(2),
        reason: 'the drawer menu group builds on first open');

    // Stock Drawer machinery: tapping the scrim beside the peek closes it.
    final drawerLeft = tester.getTopLeft(find.byType(KitDrawer));
    final drawerWidth = tester.getSize(find.byType(KitDrawer)).width;
    await tester.tapAt(Offset(drawerLeft.dx + drawerWidth + 40, 500));
    await tester.pumpAndSettle();
    expect(scaffold.isDrawerOpen, isFalse);
  });
}
