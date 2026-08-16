import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_frosted_surface.dart';

/// The platformViewSafe (vibrant fill) branch is what opaqueGlass surfaces
/// paint — a chip's solid rounded fill. In DARK mode the fill must be a
/// uniform solid: theme tint at full alpha AND a dark-appropriate rim. The
/// old code hard-painted the light-mode rim (white @ 0.45) and a light-biased
/// default tint, reading as a luminance wash over dark chips (measured on the
/// iOS 26 simulator, 2026-08-17: left 0.116 / mid 0.111 / right 0.143).
void main() {
  Widget host({required Brightness brightness, Color? tint}) => MaterialApp(
        theme: brightness == Brightness.dark
            ? ThemeData(brightness: Brightness.dark)
            : ThemeData(brightness: Brightness.light),
        home: Scaffold(
          body: Center(
            child: AppBoxKitFrostedSurface(
              borderRadius: 16,
              platformViewSafe: true,
              tint: tint,
              child: const SizedBox(width: 200, height: 60),
            ),
          ),
        ),
      );

  testWidgets(
      'kit.ui-library.frosted-surface — dark vibrant fill is uniform: full-alpha tint, dark-mode rim',
      (tester) async {
    await tester.pumpWidget(host(brightness: Brightness.dark));

    final box = tester.widget<Container>(
        find.descendant(of: find.byType(AppBoxKitFrostedSurface), matching: find.byType(Container)).first);
    final deco = box.decoration! as BoxDecoration;
    expect(deco.color!.a, 1.0,
        reason: 'no tint override → the DARK token at full alpha: solid fill, '
            'nothing shows through');
    final rim = deco.border! as Border;
    expect(rim.top.color.a, closeTo(0.16, 0.01),
        reason: 'the dark-mode rim is the subdued 0.16 hairline, not the '
            'light-mode 0.45 wash');
  });

  testWidgets(
      'kit.ui-library.frosted-surface — explicit full-alpha tint overrides the default (chip contract)',
      (tester) async {
    const tint = Color(0xFF121212);
    await tester.pumpWidget(
        host(brightness: Brightness.dark, tint: tint));

    final box = tester.widget<Container>(
        find.descendant(of: find.byType(AppBoxKitFrostedSurface), matching: find.byType(Container)).first);
    final deco = box.decoration! as BoxDecoration;
    expect(deco.color, tint,
        reason: 'an explicit opaqueGlass tint (alpha 1.0) must pass through '
            'verbatim — the GlassCard opaque branch relies on it');
  });

  testWidgets(
      'kit.ui-library.frosted-surface — light vibrant fill keeps the light rim (regression)',
      (tester) async {
    await tester.pumpWidget(host(brightness: Brightness.light));

    final box = tester.widget<Container>(
        find.descendant(of: find.byType(AppBoxKitFrostedSurface), matching: find.byType(Container)).first);
    final deco = box.decoration! as BoxDecoration;
    final rim = deco.border! as Border;
    expect(rim.top.color.a, closeTo(0.45, 0.01),
        reason: 'light mode keeps its brighter rim');
  });
}
