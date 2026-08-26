import 'package:arxa_kit_branding/arxa_kit_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Behavior suite for [ArxaKitBrandSplash] — the only runtime surface of the
/// branding kit (colors are codegen'd into the host, nothing to fake via the
/// locator). Staged through the kit's own test helpers so layout matches
/// production.
void main() {
  group('ArxaKitBrandSplash', () {
    testWidgets(
      'kit.branding.splash.brand — renders the brand mark centered horizontally '
      'at the canonical 80dp logo size',
      (tester) async {
        // given
        const brandKey = Key('brand');
        await tester.pumpWidget(arxaKitBrandSplashTestApp(
          brand: fakeArxaKitBrandMark(key: brandKey),
        ));
        // when
        final size = tester.getSize(find.byKey(brandKey));
        final center = tester.getCenter(find.byKey(brandKey));
        // then
        expect(size, const Size(ArxaKitBrandSplash.logoSize,
            ArxaKitBrandSplash.logoSize));
        expect(center.dx, 400); // default 800x600 test surface
      },
    );

    testWidgets(
      'kit.branding.splash.caption — renders the caption uppercased beneath the brand',
      (tester) async {
        // given
        await tester.pumpWidget(
            arxaKitBrandSplashTestApp(caption: 'move everyday'));
        // when
        final caption = tester.widget<Text>(find.text('MOVE EVERYDAY'));
        // then
        expect(caption.style?.letterSpacing, 2.8);
      },
    );

    testWidgets(
      'kit.branding.splash.caption — omits the caption text when none is given',
      (tester) async {
        // given
        await tester.pumpWidget(arxaKitBrandSplashTestApp());
        // when
        final texts = tester.widgetList<Text>(find.byType(Text)).toList();
        // then — only the progress readout remains
        expect(texts, hasLength(1));
        expect(texts.single.data, 'Loading · 100%');
      },
    );

    testWidgets(
      'kit.branding.splash.progress — animates the loading readout from 0% '
      'to 100% over the duration',
      (tester) async {
        // given
        await tester
            .pumpWidget(arxaKitBrandSplashTestApp(duration: const Duration(seconds: 1)));
        // when / then — pinned at the animation milestones
        expect(find.text('Loading · 0%'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Loading · 50%'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Loading · 100%'), findsOneWidget);
        expect(
          tester.widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator)).value,
          1.0,
        );
      },
    );

    testWidgets(
      'kit.branding.splash.theme — takes its background from Theme.of in '
      'light and dark themes',
      (tester) async {
        // given — injected theme literals, so the expectation is not impl-derived
        await tester.pumpWidget(arxaKitBrandSplashTestApp(
          theme: ThemeData(
              colorScheme: ColorScheme.light(surface: Colors.teal.shade100)),
        ));
        // when
        final lightBg =
            tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor;
        // then
        expect(lightBg, Colors.teal.shade100);

        // given — a dark host theme
        await tester.pumpWidget(arxaKitBrandSplashTestApp(
          theme: ThemeData(
              colorScheme:
                  ColorScheme.dark(surface: Colors.deepPurple.shade900)),
        ));
        // MaterialApp lerps theme changes over kThemeAnimationDuration —
        // settle before asserting the new theme's colors.
        await tester.pumpAndSettle();
        // when
        final darkBg =
            tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor;
        // then
        expect(darkBg, Colors.deepPurple.shade900);
      },
    );
  });
}
