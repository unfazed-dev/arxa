import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_motion/arxa_kit_motion.dart';
import 'package:arxa_kit_motion/arxa_kit_testing.dart';
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_drawer.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_frosted_surface.dart';

/// ArxaKitDrawer tests — variant rendering (glassPeek geometry + skin vs the
/// plain stock look), the stock Scaffold machinery (edge swipe / drag close
/// / scrim dismiss), the mirrored end-drawer corner, and the ArxaKitMotionScope
/// driver seam for custom choreography.
void main() {
  late GlobalKey<ScaffoldState> scaffoldKey;

  setUp(() => scaffoldKey = GlobalKey<ScaffoldState>());

  Widget host(Widget drawer, {bool end = false}) => MaterialApp(
        home: Scaffold(
          key: scaffoldKey,
          drawer: end ? null : drawer,
          endDrawer: end ? drawer : null,
          body: const Center(child: Text('host page')),
        ),
      );

  Future<void> openDrawer(WidgetTester tester, {bool end = false}) async {
    final state = scaffoldKey.currentState!;
    end ? state.openEndDrawer() : state.openDrawer();
    await tester.pumpAndSettle();
  }

  Drawer drawerWidget(WidgetTester tester) =>
      tester.widget<Drawer>(find.byType(Drawer));

  testWidgets(
      'kit.ui-library.drawer — glassPeek renders the video idiom: frosted skin, ~85% width, '
      'large rounded trailing corner', (tester) async {
    await tester.pumpWidget(host(const ArxaKitDrawer(child: Text('menu'))));
    await openDrawer(tester);

    expect(find.byType(ArxaKitFrostedSurface), findsOneWidget,
        reason: 'glassPeek skins the panel with the ADR 0010 frosted tier');
    expect(find.text('menu'), findsOneWidget);

    // The default test surface is 800x600 → the peek panel is 0.85 * 800.
    expect(tester.getSize(find.byType(Drawer)).width, closeTo(680, 0.001),
        reason: 'the host page peeks at the trailing ~15%');

    final drawer = drawerWidget(tester);
    expect(drawer.backgroundColor, Colors.transparent,
        reason: 'the skin owns the look; the Drawer Material stays clear');
    expect(drawer.elevation, 0);
    expect(drawer.clipBehavior, Clip.hardEdge);
    expect(
      drawer.shape,
      const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      reason: 'LTR leading drawer: the rounded corner sits on the trailing '
          '(right) edge the host page peeks past',
    );
  });

  testWidgets(
      'kit.ui-library.drawer — glassPeek mirrors the rounded corner for an endDrawer',
      (tester) async {
    await tester.pumpWidget(
        host(const ArxaKitDrawer(child: Text('menu')), end: true));
    await openDrawer(tester, end: true);

    expect(
      drawerWidget(tester).shape,
      const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(28)),
      ),
      reason: 'end drawer: the trailing edge flips to the left (LTR), '
          'resolved via DrawerController.alignment like stock Drawer',
    );
  });

  testWidgets(
      'kit.ui-library.drawer — plain renders the stock themed Drawer look',
      (tester) async {
    await tester.pumpWidget(host(const ArxaKitDrawer(
      variant: ArxaKitDrawerVariant.plain,
      child: Text('menu'),
    )));
    await openDrawer(tester);

    expect(find.byType(ArxaKitFrostedSurface), findsNothing,
        reason: 'plain carries no glass skin');
    expect(find.text('menu'), findsOneWidget);
    final drawer = drawerWidget(tester);
    expect(drawer.backgroundColor, isNull,
        reason: 'plain defers color, shape and elevation to the theme');
    expect(drawer.shape, isNull);
    expect(tester.getSize(find.byType(Drawer)).width, 304,
        reason: 'the stock M3 drawer width');
  });

  testWidgets(
      'kit.ui-library.drawer — width override wins over the variant default',
      (tester) async {
    await tester.pumpWidget(host(const ArxaKitDrawer(
      width: 400,
      child: Text('menu'),
    )));
    await openDrawer(tester);

    expect(tester.getSize(find.byType(Drawer)).width, 400);
  });

  testWidgets(
      'kit.ui-library.drawer — works inside a Scaffold: edge swipe opens, drag closes, '
      'scrim dismisses', (tester) async {
    await tester.pumpWidget(host(const ArxaKitDrawer(child: Text('menu'))));
    expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);

    // Edge swipe open (the stock edge-drag target lives in the first 20dp).
    await tester.dragFrom(const Offset(0, 300), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(scaffoldKey.currentState!.isDrawerOpen, isTrue);

    // Scrim dismiss — the panel is 680dp of the 800dp surface; 760 is scrim.
    await tester.tapAt(const Offset(760, 300));
    await tester.pumpAndSettle();
    expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);

    // Drag close from on the panel.
    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(400, 300), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);
  });

  testWidgets(
      'kit.ui-library.drawer — motionDriver wraps the content in a ArxaKitMotionScope driven by '
      'the passed driver (the driver path)', (tester) async {
    final driver = ArxaKitGestureDriver(vsync: tester, initialValue: 0.4);
    addTearDown(driver.dispose);
    await tester.pumpWidget(host(ArxaKitDrawer(
      motionDriver: driver,
      child: const Text('menu row').wake(),
    )));
    await openDrawer(tester);

    expect(
      tester
          .widget<ArxaKitMotionScope>(find.byType(ArxaKitMotionScope))
          .driver,
      same(driver),
      reason: 'the passed driver IS the scope driver the rows slice from',
    );
    // Slot 0 of the standard spec spans the whole eased timeline: parked at
    // 0.4 the woken row renders at easeOutCubic(0.4). Scoped to the ArxaKitWake
    // subtree — the MaterialApp's route transitions paint FadeTransitions too.
    expect(
      tester
          .widget<FadeTransition>(find.descendant(
              of: find.byType(ArxaKitWake),
              matching: find.byType(FadeTransition)))
          .opacity
          .value,
      closeTo(Curves.easeOutCubic.transform(0.4), 1e-9),
    );
  });

  testWidgets(
      'kit.ui-library.drawer — the documented menu-row recipe pins mid-flight with '
      'gestureArxaKitMotionScope', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: gestureArxaKitMotionScope(
          t: 0.5,
          child: Column(
            children: [
              for (var i = 0; i < 3; i++) Text('row $i'),
            ].wakeAll(),
          ),
        ),
      ),
    ));

    final fades = tester
        .widgetList<FadeTransition>(find.descendant(
            of: find.byType(ArxaKitWake),
            matching: find.byType(FadeTransition)))
        .toList();
    expect(fades, hasLength(3));
    expect(fades[0].opacity.value,
        closeTo(Curves.easeOutCubic.transform(0.5), 1e-9),
        reason: 'slot 0 starts at 0 → its eased position at t = 0.5');
    expect(fades[1].opacity.value, lessThan(fades[0].opacity.value),
        reason: 'stagger: later slots are less far along mid-flight');
    expect(fades[2].opacity.value, lessThan(fades[1].opacity.value));
  });

  testWidgets(
      'kit.ui-library.drawer — on the iOS 26 glass tier the peek skin takes the '
      'platform-view-safe branch (no BackdropFilter saveLayer over UiKitViews)',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isIOS: true, iosMajor: 26);
    addTearDown(ArxaKitPlatform.reset);
    await tester.pumpWidget(host(const ArxaKitDrawer(child: Text('menu'))));
    await openDrawer(tester);

    final surface = tester
        .widget<ArxaKitFrostedSurface>(find.byType(ArxaKitFrostedSurface));
    expect(surface.platformViewSafe, isTrue,
        reason: 'the host scene behind the peek panel hosts UiKitViews on '
            'iOS 26 — a BackdropFilter cannot sample them (flutter#175048), '
            'so the skin takes the vibrant-fill branch like sheet/dialog');
    expect(
      find.descendant(
          of: find.byType(Drawer), matching: find.byType(BackdropFilter)),
      findsNothing,
      reason: 'no saveLayer blur may sit over the native glass scene',
    );
  });

  testWidgets(
      'kit.ui-library.drawer — below the glass tier the peek skin keeps its blur '
      '(no platform views behind the panel; the blur IS the frosted material)',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    addTearDown(ArxaKitPlatform.reset);
    await tester.pumpWidget(host(const ArxaKitDrawer(child: Text('menu'))));
    await openDrawer(tester);

    final surface = tester
        .widget<ArxaKitFrostedSurface>(find.byType(ArxaKitFrostedSurface));
    expect(surface.platformViewSafe, isFalse);
    expect(
      find.descendant(
          of: find.byType(Drawer), matching: find.byType(BackdropFilter)),
      findsOneWidget,
      reason: 'Flutter tiers keep the blurred frosted read (ADR 0010)',
    );
  });
}
