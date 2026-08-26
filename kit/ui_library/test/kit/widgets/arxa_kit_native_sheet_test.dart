import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNButton, CNButtonStyle, CNSheetGeometryProbe, CNTabBarRouteObserver;
import 'package:flutter/cupertino.dart'
    show CupertinoSheetTransition, kCupertinoModalBarrierColor;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_frosted_surface.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_native_sheet.dart';

import 'arxa_kit_native_test_helpers.dart';

/// arxaKitShowSheet tests. It is a top-level function returning a Future,
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
  tearDown(ArxaKitPlatform.reset);

  testWidgets(
      'kit.ui-library.native-sheet — Android routes to showModalBottomSheet (no probe, no glass body)',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
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
      find.byType(ArxaKitFrostedSurface),
      findsNothing,
      reason: 'Android tier stays the M3-themed Material sheet — never glassed',
    );
  });

  testWidgets(
      'kit.ui-library.native-sheet — default tier routes to CNBottomSheet.show (geometry probe)',
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

      // One presentation for every sheet: unsized callers ride the same
      // body-sized Cupertino path as the showcase's 92%/56%/30% controls,
      // at a fixed medium height. The detent route is retired — it put a
      // second, visually different sheet chrome in the same app.
      expect(_kitGrabber, findsOneWidget,
          reason: 'iOS tier must present the body-sized Cupertino sheet');
      expect(find.byType(BottomSheet), findsNothing,
          reason: 'a Material BottomSheet on the iOS tier is the old defect');
    });
  });

  testWidgets(
      'kit.ui-library.native-sheet — default tier fills the sheet with opaque '
      'glass and draws the kit grabber', (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(_hostWithOpener());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final frosted = find.ancestor(
        of: find.text('sheet content'),
        matching: find.byType(ArxaKitFrostedSurface),
      );
      expect(frosted, findsOneWidget,
          reason: 'iOS-tier sheet content must still sit on glass (ADR 0011)');

      // borderRadius 0 is load-bearing, not incidental: CupertinoSheetRoute
      // clips its own top corners at r=12 (cupertino/sheet.dart:744), so a
      // second radius here would show as a seam inside that clip.
      final surface = tester.widget<ArxaKitFrostedSurface>(frosted);
      expect(surface.borderRadius, 0,
          reason:
              'the route owns the corner shape; the body must not re-round');
      // opaqueGlass is the default now — the on-device ruling: a translucent
      // sheet reads as a defect, not a material. Opaque base means the
      // platform-view-safe branch (no BackdropFilter saveLayer over CN views).
      expect(surface.platformViewSafe, isTrue,
          reason: 'opaque sheets must take the platform-view-safe branch');
      expect(surface.tint, isNotNull);
      expect(surface.tint!.a, 1.0,
          reason: 'the default sheet surface must be fully opaque');

      // The body owns its top edge in the body-sized path, so the grabber is
      // the kit's; the route's would sit at the route edge, not the sheet's.
      expect(_kitGrabber, findsOneWidget,
          reason: 'the body draws the grabber in the body-sized path');
      expect(_cupertinoGrabber, findsNothing,
          reason: 'exactly one pill: the route grabber must be off');
    });
  });

  testWidgets(
      'kit.ui-library.native-sheet — default tier: content tap works and dismiss returns the value',
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
      // The body-sized route dims through a plain modal barrier at the
      // Cupertino token — static, unlike the retired detent route's tracked dim.
      expect(_cupertinoBarrier, findsOneWidget,
          reason: 'the Cupertino tier must dim behind the sheet');
    });
  });

  testWidgets(
      'kit.ui-library.native-sheet — default tier honors showOverlay: false',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(_hostWithOpener(showOverlay: false));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(_cupertinoBarrier, findsNothing,
          reason: 'showOverlay: false must omit the dim entirely');
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
      'full width and publishes its own rect, not the route\'s',
      (tester) async {
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
          reason:
              'a sheet is full-bleed; anything narrower is a floating card');
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
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
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

  testWidgets(
      'kit.ui-library.native-sheet — default tier: a caller backgroundColor opts out of the glass',
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
        find.byType(ArxaKitFrostedSurface),
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
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
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
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(_hostWithOpener(showDragHandle: false));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isFalse);
  });

  testWidgets(
      'kit.ui-library.native-sheet — default tier draws the kit\'s grabber by '
      'default', (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(_hostWithOpener());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(_kitGrabber, findsOneWidget,
          reason: 'the iOS tier must show the kit-drawn grabber by default');
      expect(_cupertinoGrabber, findsNothing,
          reason: 'and exactly one: the route must not paint a second pill');
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

      expect(_kitGrabber, findsNothing,
          reason: 'showDragHandle: false must suppress the kit grabber');
      expect(_cupertinoGrabber, findsNothing,
          reason: 'and the route grabber is always off in this path');
    });
  });

  testWidgets(
      'kit.ui-library.native-sheet — the close button never overlaps sheet '
      'content: the body reserves its top-right zone', (tester) async {
    // iOS 18 override: the vendor CNButton falls back to Cupertino headless;
    // the clearance wiring is unconditional, so the glass tier inherits it.
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isIOS: true, iosMajor: 18);
    await tester.pumpWidget(_hostWithOpener());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final closeButton = tester.widget<CNButton>(find.byType(CNButton));
    expect(closeButton.config.style, CNButtonStyle.gray,
        reason: 'the filled-gray sheet-close idiom: contrast independent of '
            'backdrop luminance (glass labels measured washed out on the '
            'opaque base, iOS 26.5 simulator 2026-08-16)');
    final button = tester.getRect(find.byType(CNButton));
    final content = tester.getRect(find.text('sheet content'));
    expect(content.top, greaterThanOrEqualTo(button.bottom),
        reason: 'the glass xmark overlays content by design (HIG sheets keep '
            'an always-visible dismiss), so the body must make the room — '
            'anything right-aligned at content top otherwise sits under it');
  });

  testWidgets(
      'kit.ui-library.native-sheet — isDismissible: false withholds '
      'drag-to-dismiss on the Android tier too', (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(_hostWithOpener(isDismissible: false));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.drag(find.text('sheet content'), const Offset(0, 500));
    await tester.pumpAndSettle();

    expect(find.text('sheet content'), findsOneWidget,
        reason: 'isDismissible must withhold BOTH affordances on every tier '
            '(iOS forwards enableDrag; Android leaked it — Material default '
            'enableDrag is true)');
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
      w is SizedBox && w.width == 36 && w.height == 5 && w.key == null,
  description: 'route-drawn drag handle (36x5, framework)',
);

/// The kit-drawn grabber. The body owns its own top edge in the body-sized
/// path, so this is the only pill that should ever appear.
final Finder _kitGrabber = find.byKey(const Key('arxa_kit_sheet_grabber'));

/// The body-sized route's dim: a plain `ModalBarrier` at the Cupertino
/// barrier token — static, unlike the retired detent route's tracked dim.
final Finder _cupertinoBarrier = find.byWidgetPredicate(
  (Widget w) => w is ModalBarrier && w.color == kCupertinoModalBarrierColor,
  description: 'modal barrier at kCupertinoModalBarrierColor',
);

/// A trivial host that exposes a button which opens the native sheet from a
/// real BuildContext (the sheet needs a Navigator ancestor).
Widget _hostWithOpener({
  WidgetBuilder? sheetBuilder,
  Color? backgroundColor,
  bool showDragHandle = true,
  bool showOverlay = true,
  bool isDismissible = true,
  ValueListenable<double>? heightFactor,
  void Function(Future<Object?>)? onSheet,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () {
              final future = arxaKitShowSheet<Object?>(
                context: context,
                showDragHandle: showDragHandle,
                showOverlay: showOverlay,
                isDismissible: isDismissible,
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
