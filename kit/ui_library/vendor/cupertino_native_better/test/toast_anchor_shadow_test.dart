import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// LOCAL PATCH #11 regression tests — the toast Flutter tier's elevation.
///
/// History: the Flutter-drawn toast pill carried a `BoxShadow` inside its own
/// `BoxDecoration` while riding a tight plain `LiquidGlassContainer` anchor.
/// The shadow paints past the pill's layer bounds; on the glass tier the
/// engine's view slicer + the fade's opacity surface clip it at the pill's
/// rectangular bounding box — observed on-device (2026-08-15 clip) as a faint
/// hard-edged rectangle where the soft shadow should be (and, in worse
/// scenes, as the whole shadow vanishing).
///
/// The fix: the pill paints NO shadow of its own, ever. Elevation comes from
/// the anchor's `LiquidGlassConfig.shadow` — a native CALayer shadow on the
/// glass tier (composited by Core Animation, immune to Flutter layer bounds)
/// and a shape-matched ShapeDecoration shadow on the fallback tier.
void main() {
  Future<void> withPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    final saved = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = saved;
    }
  }

  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  Future<void> fireToast(WidgetTester tester) async {
    await tester.pumpWidget(host(Builder(builder: (ctx) {
      return TextButton(
        onPressed: () => CNToast.info(
          context: ctx,
          message: 'shadow spec',
          useGlassEffect: false,
        ),
        child: const Text('fire'),
      );
    })));
    await tester.tap(find.text('fire'));
    await tester.pump(); // mount the toast overlay entry
  }

  /// The toast pill is the capsule-radius-100 Container in the overlay.
  Finder findPill() => find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        if (d is! BoxDecoration) return false;
        final r = d.borderRadius;
        return r is BorderRadius && r.topLeft == const Radius.circular(100);
      });

  /// Drains the toast's auto-dismiss Timer so no timer is pending at teardown.
  Future<void> drainToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
  }

  testWidgets(
      'LOCAL PATCH #11: toast anchor config carries the native shadow spec',
      (tester) async {
    await withPlatform(TargetPlatform.android, () async {
      await fireToast(tester);

      final anchor = tester.widget<LiquidGlassContainer>(
        find.byType(LiquidGlassContainer),
      );
      expect(anchor.config.effect, CNGlassEffect.plain,
          reason: 'the toast anchor stays the plain slicer anchor');
      final shadow = anchor.config.shadow;
      expect(shadow, isNotNull,
          reason: 'elevation is declared on the anchor, not the pill');
      expect(shadow!.radius, 16.0);
      expect(shadow.opacity, 0.15);
      expect(shadow.offset, const Offset(0, 6));
      await drainToast(tester);
    });
  });

  testWidgets('LOCAL PATCH #11: the toast pill paints no shadow of its own',
      (tester) async {
    await withPlatform(TargetPlatform.android, () async {
      await fireToast(tester);

      expect(findPill(), findsOneWidget,
          reason: 'test sanity: the toast pill must be mounted');
      for (final container in tester.widgetList<Container>(findPill())) {
        final decoration = container.decoration;
        if (decoration is BoxDecoration) {
          expect(
            decoration.boxShadow,
            isNull,
            reason: 'a pill-painted BoxShadow spills past the anchor rect and '
                'renders as a hard-edged rectangle on the glass tier '
                '(2026-08-15 clip); elevation belongs to the anchor config',
          );
        }
      }
      await drainToast(tester);
    });
  });

  testWidgets(
      'LOCAL PATCH #11: fallback tier still shows a capsule-shaped shadow '
      '(shape shadow painter under the anchor)', (tester) async {
    await withPlatform(TargetPlatform.android, () async {
      await fireToast(tester);

      // On the fallback tier the container wraps its child with a
      // ShapeDecoration shadow matched to the configured shape (capsule), so
      // pre-26 devices keep the exact elevation the old in-decoration
      // BoxShadow produced.
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
      await drainToast(tester);
    });
  });
}
