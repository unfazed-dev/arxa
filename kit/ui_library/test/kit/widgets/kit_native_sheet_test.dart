import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNSheetGeometryProbe;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/platform/kit_platform.dart';
import 'package:ui_library/widgets/kit_frosted_surface.dart';
import 'package:ui_library/widgets/kit_native_sheet.dart';

import 'native_test_helpers.dart';

/// kitShowNativeSheet tests. It is a top-level function returning a Future,
/// so the assertions are branch-taken + behavior: the sheet content renders,
/// the right tier's machinery appears (plain [showModalBottomSheet] on
/// Android vs [CNBottomSheet.show]'s injected [CNSheetGeometryProbe] on the
/// iOS / default tier), and — on the iOS tier only — the content sits in the
/// ADR 0011 glass body (a [KitFrostedSurface] panel with a grabber, on a
/// transparent route). Neither tier builds a UiKitView, so no platform
/// channel is ever touched; the default-tier tests still run under
/// [withAndroidFallback] per the shared helper's convention.
void main() {
  tearDown(KitPlatform.reset);

  testWidgets(
      'Android routes to showModalBottomSheet (no probe, no glass body)',
      (tester) async {
    KitPlatform.override = const KitPlatformOverride(isAndroid: true);
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
      find.byType(KitFrostedSurface),
      findsNothing,
      reason: 'Android tier stays the M3-themed Material sheet — never glassed',
    );
  });

  testWidgets('default tier routes to CNBottomSheet.show (geometry probe)',
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

  testWidgets('default tier wraps content in the glass body with a grabber',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(_hostWithOpener());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final frosted = find.ancestor(
        of: find.text('sheet content'),
        matching: find.byType(KitFrostedSurface),
      );
      expect(
        frosted,
        findsOneWidget,
        reason: 'iOS-tier sheet content must sit in a KitFrostedSurface panel',
      );
      final surface = tester.widget<KitFrostedSurface>(frosted);
      expect(surface.borderRadius, 28, reason: 'the sheet material corners');
      expect(surface.blur, 30, reason: 'the prominent sheet material blur');
      expect(
        find.byKey(const ValueKey<String>('kitNativeSheetGrabber')),
        findsOneWidget,
        reason: 'the floating-sheet idiom shows a grabber above the content',
      );
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
        Colors.transparent,
        reason: 'the route chrome is transparent so the glass body reads',
      );
    });
  });

  testWidgets('default tier: content tap works and dismiss returns the value',
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

  testWidgets('default tier: barrier tap dismisses with null', (tester) async {
    Future<Object?>? sheetFuture;
    await withAndroidFallback(() async {
      await tester.pumpWidget(
        _hostWithOpener(onSheet: (future) => sheetFuture = future),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(400, 50));
      await tester.pumpAndSettle();

      expect(
        await sheetFuture,
        isNull,
        reason: 'isDismissible stays honored through the glass body',
      );
      expect(find.text('sheet content'), findsNothing);
    });
  });

  testWidgets('default tier: a caller backgroundColor opts out of the glass',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(_hostWithOpener(backgroundColor: Colors.red));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('sheet content'), findsOneWidget);
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
        Colors.red,
        reason: 'a caller-supplied backgroundColor still wins',
      );
      expect(
        find.byType(KitFrostedSurface),
        findsNothing,
        reason: 'explicit chrome opts out of the glass body',
      );
      expect(
        find.byKey(const ValueKey<String>('kitNativeSheetGrabber')),
        findsNothing,
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
              final future = kitShowNativeSheet<Object?>(
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
