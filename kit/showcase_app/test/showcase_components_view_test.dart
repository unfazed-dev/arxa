// Widget tests for the ADR 0011 components showcase surface — the demos
// themselves are proven in appbox_kit_ui_library's per-component tests; these pin the
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
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'helpers.dart';

/// The Android toast tier renders through stacked_services' GetX snackbar,
/// which needs a GetMaterialApp the test harness doesn't have — stub it (same
/// pattern as appbox_kit_ui_library's own notification-service tests) and record calls
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
  tearDownAll(() => appBoxKitLocator.reset());

  setUp(() {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    if (appBoxKitLocator.isRegistered<SnackbarService>()) {
      appBoxKitLocator.unregister<SnackbarService>();
    }
    snackbar = _StubSnackbarService();
    appBoxKitLocator.registerSingleton<SnackbarService>(snackbar);
  });
  tearDown(AppBoxKitPlatform.reset);

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

    expect(find.byType(AppBoxKitFrostedSurface), findsWidgets,
        reason: 'the explicit frosted content-tier card');
    expect(find.byType(AppBoxKitChipCarousel), findsOneWidget);
    expect(find.byType(AppBoxKitChip), findsNWidgets(10));
    expect(find.byType(AppBoxKitListSection), findsOneWidget,
        reason: 'the settings group in the body (the drawer menu group only '
            'builds once the drawer first opens)');
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).drawer, isNotNull,
        reason: 'the glassPeek AppBoxKitDrawer is configured on the Scaffold '
            '(its subtree only builds once opened)');
    expect(find.byType(AppBoxKitNativeInputBar), findsOneWidget);
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

  testWidgets('each preset button presents the sheet at its own height',
      (tester) async {
    await pumpView(tester);

    for (final String preset in const ['92%', '56%', '30%']) {
      await tester.tap(find.text(preset));
      await tester.pumpAndSettle();
      expect(find.text('Frosted sheet body'), findsOneWidget,
          reason: '$preset must present the sheet');
      // Twice: once on the card's button, once as the open sheet's readout.
      // One occurrence would mean the sheet opened at some other height.
      expect(find.text(preset), findsNWidgets(2),
          reason: 'the open sheet reports the height the button asked for');

      await tester.tapAt(const Offset(20, 20)); // overlay dismiss
      await tester.pumpAndSettle();
      expect(find.text('Frosted sheet body'), findsNothing,
          reason: 'tapping the overlay closes the sheet');
    }
  });

  testWidgets('the slider inside the sheet drives its height', (tester) async {
    await pumpView(tester);

    await tester.tap(find.text('30%'));
    await tester.pumpAndSettle();
    expect(find.text('30%'), findsWidgets);

    // Invoking onChanged directly rather than dragging: the slider resolves to
    // a different native control per tier, and what is under test here is the
    // wiring from the control to the sheet's height, not either tier's gesture
    // handling (the kit suite covers the resize itself).
    final AppBoxKitNativeSlider slider =
        tester.widget<AppBoxKitNativeSlider>(find.byType(AppBoxKitNativeSlider));
    expect(slider.min, 0.20, reason: 'minimum height is 20% of screen');
    expect(slider.max, 0.92,
        reason: 'maximum is the Cupertino route default, 1 - _kTopGapRatio');

    slider.onChanged!(0.75);
    await tester.pump();
    expect(find.text('75%'), findsOneWidget,
        reason: 'the slider and the sheet share one height notifier');
  });

  testWidgets('Show center toast fires the center pill', (tester) async {
    await pumpView(tester);

    await tester.tap(find.text('Show center toast'));
    await tester.pump(); // mount the pill's overlay entry
    expect(find.byKey(const Key('appBoxKitCenterToastPill')), findsOneWidget);
    expect(find.text('Centered'), findsOneWidget);

    // Auto-dismiss (3s default) — elapse fake time so no timer is pending.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('appBoxKitCenterToastPill')), findsNothing);
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
    expect(find.byType(AppBoxKitDrawer), findsOneWidget,
        reason: 'the opened drawer builds the AppBoxKitDrawer (glassPeek) subtree');
    expect(find.text('About'), findsOneWidget,
        reason: 'menu rows are AppBoxKitListTiles inside a AppBoxKitListSection');
    expect(find.byType(AppBoxKitListSection), findsNWidgets(2),
        reason: 'the drawer menu group builds on first open');

    // Stock Drawer machinery: tapping the scrim beside the peek closes it.
    final drawerLeft = tester.getTopLeft(find.byType(AppBoxKitDrawer));
    final drawerWidth = tester.getSize(find.byType(AppBoxKitDrawer)).width;
    await tester.tapAt(Offset(drawerLeft.dx + drawerWidth + 40, 500));
    await tester.pumpAndSettle();
    expect(scaffold.isDrawerOpen, isFalse);
  });

  // The list's top padding must be read from a context BELOW the chrome
  // scaffold (the view wraps its body in a Builder for exactly this): the
  // glass tier's floating chrome raises MediaQuery.padding.top for its body
  // subtree ONLY. Read at the view's own context it is wrong on both tiers —
  // unraised on glass, and the unstripped status bar on boxed.
  group('list top padding resolves below the chrome', () {
    const double statusBar = 44;

    Future<EdgeInsets> pumpAndReadPadding(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(top: statusBar);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      await tester.pumpWidget(const MaterialApp(home: ShowcaseComponentsView()));
      await tester.pump();
      return tester
          .widget<AppBoxKitEdgeAwareListView>(
              find.byType(AppBoxKitEdgeAwareListView))
          .padding!
          .resolve(TextDirection.ltr);
    }

    testWidgets('boxed tier takes the bare inset — Scaffold already stripped it',
        (tester) async {
      // setUp's Android override is the boxed branch.
      expect((await pumpAndReadPadding(tester)).top, abxSize16,
          reason: 'a boxed tier that leaks the status bar into the list is the '
              'padding read from above the scaffold');
    });

    testWidgets('glass tier adds the status bar + floating-bar block',
        (tester) async {
      AppBoxKitPlatform.override =
          const AppBoxKitPlatformOverride(isIOS: true, iosMajor: 26);
      expect((await pumpAndReadPadding(tester)).top,
          abxSize16 + statusBar + kAppBoxKitFloatingBarBlockHeight,
          reason: 'missing the raise means the padding was read above the '
              'floating chrome, tucking the first card under the bar');
    });
  });
}
