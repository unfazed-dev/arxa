import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNSheetGeometryProbe;
import 'package:flutter/cupertino.dart' show CupertinoSheetTransition;
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
      // not one". The Cupertino route is what supplies the real presentation:
      // the page behind scales down and rounds its corners.
      expect(find.byType(CupertinoSheetTransition), findsWidgets,
          reason: 'iOS tier must route through showCupertinoSheet');
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
      'kit.ui-library.native-sheet — default tier: an outside tap does NOT '
      'dismiss, matching the Cupertino route', (tester) async {
    // Deliberate behaviour change, recorded so it is not mistaken for a
    // regression. `CupertinoSheetRoute.barrierDismissible` is false and its
    // barrierColor is transparent (cupertino/sheet.dart:777,780) — there is no
    // dim scrim to tap, exactly as on iOS, where you drag a sheet down instead.
    // `isDismissible` therefore maps to `enableDrag`, not to barrier-tap.
    //
    // The previous version of this test awaited the sheet future after tapping
    // the barrier; under the Cupertino route that future never completes, so
    // the test hung rather than failed.
    await withAndroidFallback(() async {
      await tester.pumpWidget(_hostWithOpener());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('sheet content'), findsOneWidget);

      await tester.tapAt(const Offset(400, 50));
      await tester.pumpAndSettle();

      expect(find.text('sheet content'), findsOneWidget,
          reason: 'the Cupertino sheet has no dismissible barrier to tap');
    });
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
}

/// A trivial host that exposes a button which opens the native sheet from a
/// real BuildContext (the sheet needs a Navigator ancestor).
Widget _hostWithOpener({
  WidgetBuilder? sheetBuilder,
  Color? backgroundColor,
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
