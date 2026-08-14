import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNSheetGeometryProbe, CNTabBarRouteObserver;
import 'package:flutter/cupertino.dart' show CupertinoSheetTransition;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_frosted_surface.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_sheet.dart';

import 'appbox_kit_native_test_helpers.dart';

/// appBoxKitShowSheet tests. It is a top-level function returning a Future,
/// so the assertions are branch-taken + behavior: the sheet content renders,
/// the right tier's machinery appears (plain [showModalBottomSheet] on
/// Android vs the Cupertino sheet route plus [CNSheetGeometryProbe] on the
/// iOS / default tier), and — on the iOS tier only — the content sits on a
/// full-bleed glass surface whose corners and grabber are owned by the route.
/// Neither tier builds a UiKitView, so no platform channel is ever touched;
/// the default-tier tests still run under [withAndroidFallback] per the
/// shared helper's convention.
///
/// The iOS tier used to be a Material `showModalBottomSheet` with transparent
/// chrome wrapping a floating inset card — a floating panel, not a sheet. The
/// assertions here were rewritten alongside that fix, so several of them
/// invert on purpose (no `BottomSheet`, no kit grabber, no barrier dismiss).
/// See `docs/plans/sheet-and-theme-propagation-fixes.md`.
void main() {
  tearDown(AppBoxKitPlatform.reset);

  testWidgets(
      'kit.ui-library.native-sheet — Android routes to showModalBottomSheet (no probe, no glass body)',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(_hostWithOpener());

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text('sheet content'),
      findsOneWidget,
      reason: 'the Android sheet must build and show its content',
    );
    expect(
      find.byType(CNSheetGeometryProbe),
      findsNothing,
      reason: 'Android tier uses plain showModalBottomSheet, not CNBottomSheet',
    );
    expect(
      find.byType(AppBoxKitFrostedSurface),
      findsNothing,
      reason: 'Android tier stays the M3-themed Material sheet — never glassed',
    );
  });

  testWidgets('kit.ui-library.native-sheet — default tier routes to CNBottomSheet.show (geometry probe)',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(_hostWithOpener());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.text('sheet content'),
        findsOneWidget,
        reason: 'the CN sheet must build and show its content',
      );
      expect(
        find.byType(CNSheetGeometryProbe),
        findsOneWidget,
        reason: 'default tier routes through CNBottomSheet.show',
      );
    });
  });

  testWidgets(
      'kit.ui-library.native-sheet — default tier presents a Cupertino sheet, '
      'not a Material one', (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(_hostWithOpener());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The whole point of the change. The old iOS tier was a Material
      // `showModalBottomSheet` with transparent chrome around a floating
      // inset card, which read on device as "similar to a bottom sheet but
      // not one". The CN detent route is what supplies the real presentation:
      // detent snapping, a route-drawn grabber, and a detent-tracked dim.
      expect(_routeGrabber, findsOneWidget,
          reason: 'iOS tier must route through the CN detent sheet route');
      expect(find.byType(BottomSheet), findsNothing,
          reason: 'a Material BottomSheet on the iOS tier is the old defect');
    });
  });

  testWidgets(
      'kit.ui-library.native-sheet — default tier fills the sheet with glass '
      'and leaves the grabber to the route', (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(_hostWithOpener());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final frosted = find.ancestor(
        of: find.text('sheet content'),
        matching: find.byType(AppBoxKitFrostedSurface),
      );
      expect(frosted, findsOneWidget,
          reason: 'iOS-tier sheet content must still sit on glass (ADR 0011)');

      // borderRadius 0 is load-bearing, not incidental: CupertinoSheetRoute
      // clips its own top corners at r=12 (cupertino/sheet.dart:744), so a
      // second radius here would show as a seam inside that clip.
      final surface = tester.widget<AppBoxKitFrostedSurface>(frosted);
      expect(surface.borderRadius, 0,
          reason: 'the route owns the corner shape; the body must not re-round');
      expect(surface.blur, 30, reason: 'the prominent sheet material blur');

      // The route draws the grabber itself when showDragHandle is set. If the
      // kit also painted one there would visibly be two pills.
      expect(
        find.byKey(const ValueKey<String>('appBoxKitNativeSheetGrabber')),
        findsNothing,
        reason: 'the kit must not paint a grabber over the route\'s own',
      );
    });
  });

  testWidgets('kit.ui-library.native-sheet — default tier: content tap works and dismiss returns the value',
      (tester) async {
    Future<Object?>? sheetFuture;
    await withAndroidFallback(() async {
      await tester.pumpWidget(_hostWithOpener(
        onSheet: (future) => sheetFuture = future,
        sheetBuilder: (ctx) => ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(42),
          child: const Text('return 42'),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('return 42'));
      await tester.pumpAndSettle();

      expect(
        await sheetFuture,
        42,
        reason: 'Navigator.pop(ctx, value) must resolve the sheet future',
      );
      expect(find.text('return 42'), findsNothing);
    });
  });

  testWidgets(
      'kit.ui-library.native-sheet — default tier: a tap on the overlay '
      'dismisses', (tester) async {
    // This assertion is the inverse of the one it replaces, and the old one was
    // never load-bearing: it tapped Offset(400, 50) on an 800x600 surface, while
    // the route's box starts at 0.08 * 600 = y=48. It was tapping two pixels
    // *inside* the sheet, so it would have passed with or without a barrier.
    //
    // The kit now supplies the barrier the framework route withholds, so tapping
    // the genuinely uncovered strip must dismiss.
    await withAndroidFallback(() async {
      await tester.pumpWidget(_hostWithOpener());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('sheet content'), findsOneWidget);

      // y=20 is above the route box's top edge at y=48 — real barrier, not
      // sheet.
      await tester.tapAt(const Offset(400, 20));
      await tester.pumpAndSettle();

      expect(find.text('sheet content'), findsNothing,
          reason: 'the overlay is tappable and dismisses the sheet');
    });
  });

  // These two are deliberately separate tests. Pumping a second host inside one
  // test reuses the root element and its Navigator, so the first sheet stays
  // pushed and the second assertion measures the first sheet's barrier.
  testWidgets('kit.ui-library.native-sheet — default tier paints a dim overlay',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(_hostWithOpener());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // The dim tracks the detent — 0 at the opening (lowest) detent so the
      // page behind stays legible, opaque at the top — matching the reference
      // recording. Drag to the top detent before asserting visibility.
      await tester.drag(_routeGrabber, const Offset(0, -400));
      await tester.pumpAndSettle();
      final Color dim = tester.widget<ColoredBox>(_detentDim).color;
      expect(dim.a, greaterThan(0),
          reason: 'the Cupertino tier must dim at the top detent');
    });
  });

  testWidgets(
      'kit.ui-library.native-sheet — default tier honors showOverlay: false',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(_hostWithOpener(showOverlay: false));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cn_detent_sheet_dim')), findsNothing,
          reason: 'showOverlay: false must omit the dim layer entirely');
    });
  });

  testWidgets(
      'kit.ui-library.native-sheet — default tier: heightFactor sizes the '
      'sheet and a change resizes it live', (tester) async {
    await withAndroidFallback(() async {
      final ValueNotifier<double> height = ValueNotifier<double>(0.30);
      addTearDown(height.dispose);

      await tester.pumpWidget(_hostWithOpener(heightFactor: height));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // 800x600 surface: 30% of screen height.
      expect(_sheetHeight(tester), closeTo(180, 0.5),
          reason: 'heightFactor is a fraction of screen height');

      final int routesBefore =
          tester.widgetList(find.byType(CupertinoSheetTransition)).length;

      height.value = 0.56;
      await tester.pump();

      expect(_sheetHeight(tester), closeTo(336, 0.5),
          reason: 'the live sheet must follow the notifier without re-pushing');
      expect(
        tester.widgetList(find.byType(CupertinoSheetTransition)).length,
        routesBefore,
        reason: 'resizing must not push a second route — that would re-animate',
      );
    });
  });

  testWidgets(
      'kit.ui-library.native-sheet — default tier: the space above a short '
      'sheet reaches the overlay', (tester) async {
    // The point of the sized path: the gap must stay tappable. Filling it with a
    // transparent ColoredBox would look identical and swallow the tap, because
    // _RenderColoredBox is HitTestBehavior.opaque even at alpha 0
    // (widgets/basic.dart:8528-8532).
    await withAndroidFallback(() async {
      final ValueNotifier<double> height = ValueNotifier<double>(0.30);
      addTearDown(height.dispose);

      await tester.pumpWidget(_hostWithOpener(heightFactor: height));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('sheet content'), findsOneWidget);

      // The sheet occupies the bottom 180px of 600; tap well above it.
      await tester.tapAt(const Offset(400, 200));
      await tester.pumpAndSettle();

      expect(find.text('sheet content'), findsNothing,
          reason: 'the empty area above a short sheet must hit the barrier, '
              'not an invisible box belonging to the sheet');
    });
  });

  testWidgets(
      'kit.ui-library.native-sheet — default tier: the sized sheet spans the '
      'full width and publishes its own rect, not the route\'s', (tester) async {
    // Two regressions in one assertion, both invisible to a height-only check.
    //
    // Width: Align hands down loose constraints, so a SizedBox given only a
    // height collapses to its content's intrinsic width — a centered floating
    // card, which is precisely the shape the Cupertino route replaced.
    //
    // Rect: CNBottomSheet's automatic probe wraps the whole pageBuilder output,
    // which in this path is the Align filling the route (92%). Publishing that
    // would tell every ModalHideMixin widget on the host page it is covered when
    // 62% of the screen is clear, tearing down native chrome for nothing — so
    // the body places the probe on the sized box instead.
    await withAndroidFallback(() async {
      final ValueNotifier<double> height = ValueNotifier<double>(0.30);
      addTearDown(height.dispose);

      await tester.pumpWidget(_hostWithOpener(heightFactor: height));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Exactly one probe, asserted separately from the rect it publishes.
      // Two probes republish into the same ValueNotifier every frame on a
      // last-writer-wins basis: the rect can still come out right purely
      // because the inner one happens to fire second, so a correct rect is not
      // evidence that only one probe exists. The dispose guard compares the
      // published rect to its own last value and cannot tell whose it was.
      expect(find.byType(CNSheetGeometryProbe), findsOneWidget,
          reason: 'the vendor wrapper must not also inject its own probe when '
              'the body is bottom-anchored');

      final Rect? published = CNTabBarRouteObserver.topModalRect.value;
      expect(published, isNotNull,
          reason: 'the sized path must still publish a rect at all');
      // 800x600 surface, sheet is the bottom 30%.
      expect(published!.height, closeTo(180, 0.5),
          reason: 'the published rect must be the visible sheet, not the '
              'route box (552)');
      expect(published.top, closeTo(420, 0.5));
      expect(published.width, closeTo(800, 0.5),
          reason: 'a sheet is full-bleed; anything narrower is a floating card');
    });
  });

  testWidgets(
      'kit.ui-library.native-sheet — default tier: the sized path draws exactly '
      'one grabber, and it is the kit\'s', (tester) async {
    await withAndroidFallback(() async {
      final ValueNotifier<double> height = ValueNotifier<double>(0.30);
      addTearDown(height.dispose);

      await tester.pumpWidget(_hostWithOpener(heightFactor: height));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(_kitGrabber, findsOneWidget,
          reason: 'the body owns its top edge here, so it draws the grabber');
      expect(_cupertinoGrabber, findsNothing,
          reason: 'the route\'s grabber would sit at the route\'s edge (92%), '
              'not the sheet\'s — it must be switched off');
    });
  });

  testWidgets(
      'kit.ui-library.native-sheet — Android: heightFactor sizes the sheet',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    final ValueNotifier<double> height = ValueNotifier<double>(0.30);
    addTearDown(height.dispose);

    await tester.pumpWidget(_hostWithOpener(heightFactor: height));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final Finder sized = find.ancestor(
      of: find.text('sheet content'),
      matching: find.byWidgetPredicate(
        (Widget w) => w is SizedBox && w.height == 180,
      ),
    );
    expect(sized, findsOneWidget,
        reason: 'the Material tier sizes to its child, so the child carries '
            'the height');
  });

  testWidgets('kit.ui-library.native-sheet — default tier: a caller backgroundColor opts out of the glass',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(_hostWithOpener(backgroundColor: Colors.red));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('sheet content'), findsOneWidget);
      final coloured = find.ancestor(
        of: find.text('sheet content'),
        matching: find.byWidgetPredicate(
          (Widget w) => w is ColoredBox && w.color == Colors.red,
        ),
      );
      expect(coloured, findsOneWidget,
          reason: 'a caller-supplied backgroundColor still wins');
      expect(
        find.byType(AppBoxKitFrostedSurface),
        findsNothing,
        reason: 'explicit chrome opts out of the glass body',
      );
    });
  });

  // ---------------------------------------------------------------------
  // Drag handle: on by default on BOTH tiers.
  //
  // Android previously had NO handle. The kit passed nothing, and Material
  // resolves `showDragHandle ?? (enableDrag && (sheetTheme.showDragHandle ??
  // false))` (`material/bottom_sheet.dart:1161`) — with no
  // `bottomSheetTheme.showDragHandle` anywhere in the kit that is `false`. So
  // this is a behaviour fix on Android, not just a new knob.
  // ---------------------------------------------------------------------

  testWidgets(
      'kit.ui-library.native-sheet — Android shows a drag handle by default',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(_hostWithOpener());

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isTrue,
        reason: 'without an explicit value Material resolves this to false via '
            'the theme, leaving a draggable sheet with no visible affordance');
  });

  testWidgets(
      'kit.ui-library.native-sheet — Android honors showDragHandle: false',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(_hostWithOpener(showDragHandle: false));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isFalse);
  });

  testWidgets(
      'kit.ui-library.native-sheet — default tier draws the route\'s grabber by '
      'default', (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(_hostWithOpener());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(_cupertinoGrabber, findsOneWidget,
          reason: 'the iOS tier must show the route-drawn grabber by default');
      expect(
        find.byKey(const ValueKey<String>('appBoxKitNativeSheetGrabber')),
        findsNothing,
        reason: 'and exactly one: the kit must not paint a second pill',
      );
    });
  });

  testWidgets(
      'kit.ui-library.native-sheet — default tier honors showDragHandle: false',
      (tester) async {
    // Separate test on purpose. Re-pumping a second `_hostWithOpener()` inside
    // one test reuses the MaterialApp element and therefore its Navigator, so
    // the first sheet stays pushed and its grabber is still found — the
    // opt-out assertion then fails against the *previous* sheet.
    await withAndroidFallback(() async {
      await tester.pumpWidget(_hostWithOpener(showDragHandle: false));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(_cupertinoGrabber, findsNothing,
          reason: 'showDragHandle: false must reach the Cupertino route');
    });
  });
}

/// The Cupertino grabber's exact geometry, from Apple's Figma files via
/// `cupertino/sheet.dart:704-708`: 36x5. Matching the size is what
/// distinguishes "the route drew it" from "something else here is small".
///
/// The kit reproduces that same geometry in the sized path, so size alone can
/// no longer say *which* drew it — hence the key exclusion. Without it, a "there
/// is exactly one grabber" assertion would pass with both on screen.
final Finder _cupertinoGrabber = find.byWidgetPredicate(
  (Widget w) =>
      w is SizedBox &&
      w.width == 36 &&
      w.height == 5 &&
      (w.key == null || w.key == const Key('cn_detent_sheet_grabber')),
  description: 'route-drawn drag handle (36x5, framework or CN detent route)',
);

/// The CN detent route's own grabber, by key. Presence proves the unsized
/// path went through the detent route rather than the framework sheet.
final Finder _routeGrabber =
    find.byKey(const Key('cn_detent_sheet_grabber'));

/// The kit-drawn grabber, used only when the body owns its own top edge.
final Finder _kitGrabber = find.byKey(const Key('appbox_kit_sheet_grabber'));

/// The detent route's dim layer: a `ColoredBox` whose alpha tracks the detent
/// (0 at the lowest, full at the top), not a `ModalBarrier` — so visibility is
/// asserted by reading the colour, after dragging to the top detent.
final Finder _detentDim = find.descendant(
  of: find.byKey(const Key('cn_detent_sheet_dim')),
  matching: find.byType(ColoredBox),
);

/// A trivial host that exposes a button which opens the native sheet from a
/// real BuildContext (the sheet needs a Navigator ancestor).
Widget _hostWithOpener({
  WidgetBuilder? sheetBuilder,
  Color? backgroundColor,
  bool showDragHandle = true,
  bool showOverlay = true,
  ValueListenable<double>? heightFactor,
  void Function(Future<Object?>)? onSheet,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () {
              final future = appBoxKitShowSheet<Object?>(
                context: context,
                showDragHandle: showDragHandle,
                showOverlay: showOverlay,
                heightFactor: heightFactor,
                backgroundColor: backgroundColor,
                builder: sheetBuilder ??
                    (_) => const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('sheet content'),
                        ),
              );
              onSheet?.call(future);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

/// Height of the presented sheet body, measured off the widget that owns the
/// height rather than off the text inside it.
double _sheetHeight(WidgetTester tester) {
  final Finder surface = find.ancestor(
    of: find.text('sheet content'),
    matching: find.byType(ClipRSuperellipse),
  );
  return tester.getSize(surface.first).height;
}
