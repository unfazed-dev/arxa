import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_frosted_surface.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_glass_luminance.dart';

/// ArxaKitFrostedSurface tests — the ADR 0010 content-layer frosted tier:
/// BackdropFilter blur + saturation, theme-derived tint, rim highlight.
void main() {
  Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? ThemeData.light(), home: Scaffold(body: child));

  BoxDecoration surfaceDecoration(WidgetTester tester) {
    final container = tester.widget<Container>(find.descendant(
        of: find.byType(BackdropFilter), matching: find.byType(Container)));
    return container.decoration! as BoxDecoration;
  }

  testWidgets(
      'kit.ui-library.frosted-surface — renders the child behind a BackdropFilter, clipped to the '
      'rounded rect', (tester) async {
    await tester.pumpWidget(host(const ArxaKitFrostedSurface(
      borderRadius: 24,
      padding: EdgeInsets.all(8),
      child: Text('frosted'),
    )));

    expect(find.text('frosted'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget,
        reason: 'the frosted tier blurs the backdrop');
    expect(
      tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
      BorderRadius.circular(24),
      reason: 'borderRadius param drives the clip',
    );
    expect(
      tester
          .widget<Padding>(find.descendant(
              of: find.byType(BackdropFilter), matching: find.byType(Padding)))
          .padding,
      const EdgeInsets.all(9.0),
      reason: 'the 8dp padding param + the 1dp rim border, which Container '
          'always reserves so content never paints over the rim',
    );
  });

  testWidgets(
      'kit.ui-library.frosted-surface — tint + rim highlight ride the theme (light)',
      (tester) async {
    final light = ThemeData.light();
    // One theme per test: a second pumpWidget with a different MaterialApp
    // theme does not reliably re-propagate the inherited theme in
    // flutter_test, so the light/dark pair is split.
    await tester.pumpWidget(
        host(const ArxaKitFrostedSurface(child: Text('x')), theme: light));
    final deco = surfaceDecoration(tester);
    expect(deco.color,
        light.colorScheme.surfaceContainerLowest.withValues(alpha: 0.72),
        reason: 'light material = card token at 72%');
    expect((deco.border! as Border).top.color,
        Colors.white.withValues(alpha: 0.45));
  });

  testWidgets(
      'kit.ui-library.frosted-surface — tint + rim highlight ride the theme (dark)',
      (tester) async {
    final dark = ThemeData.dark();
    await tester.pumpWidget(
        host(const ArxaKitFrostedSurface(child: Text('x')), theme: dark));
    final deco = surfaceDecoration(tester);
    expect(deco.color,
        dark.colorScheme.surfaceContainerLowest.withValues(alpha: 0.55),
        reason: 'dark material = card token at 55%');
    expect((deco.border! as Border).top.color,
        Colors.white.withValues(alpha: 0.16));
  });

  testWidgets(
      'kit.ui-library.frosted-surface — tint override wins over the theme-derived default',
      (tester) async {
    // Translucent: a fully opaque tint now takes the no-saveLayer branch
    // (the auto-opaque law below), so the blurred branch's override pin
    // uses a translucent tint.
    final tint = Colors.red.withValues(alpha: 0.5);
    await tester.pumpWidget(
        host(ArxaKitFrostedSurface(tint: tint, child: const Text('x'))));
    expect(surfaceDecoration(tester).color, tint);
  });

  testWidgets(
      'kit.ui-library.frosted-surface — a fully opaque tint takes the no-saveLayer branch automatically',
      (tester) async {
    // The auto-opaque law: a fully opaque fill makes the backdrop blur
    // invisible anyway (rule 13), so an opaque tint alone drops the
    // BackdropFilter — no platformViewSafe flag required. Opacity is a
    // discrete mode switch, not an interpolation: callers must not
    // animate tint alpha across 1.0.
    await tester.pumpWidget(host(const ArxaKitFrostedSurface(
      tint: Color(0xFFF5F5F5),
      child: Text('x'),
    )));

    expect(find.byType(BackdropFilter), findsNothing,
        reason: 'blur under a fully opaque fill is invisible work and a '
            'saveLayer hazard over platform views (flutter#175048)');
    final container = tester.widget<Container>(find
        .ancestor(of: find.text('x'), matching: find.byType(Container))
        .first);
    expect((container.decoration! as BoxDecoration).color,
        const Color(0xFFF5F5F5));
  });

  testWidgets(
      'kit.ui-library.frosted-surface — the opaque branch publishes an opaque luminance scope',
      (tester) async {
    ArxaKitGlassLuminance? seen;
    await tester.pumpWidget(host(ArxaKitFrostedSurface(
      platformViewSafe: true,
      child: Builder(builder: (context) {
        seen = ArxaKitGlassLuminance.maybeOf(context);
        return const SizedBox();
      }),
    )));

    expect(seen, isNotNull,
        reason: 'every frosted surface declares its luminance so native '
            'glass controls adapt automatically');
    expect(seen!.opaque, isTrue);
    expect(seen!.brightness, Brightness.light,
        reason: 'the light-theme card token at full alpha is a bright base');
    expect(seen!.demotesGlass, isTrue);
  });

  testWidgets(
      'kit.ui-library.frosted-surface — the blurred branch publishes a translucent scope (never demotes)',
      (tester) async {
    ArxaKitGlassLuminance? seen;
    await tester.pumpWidget(host(ArxaKitFrostedSurface(
      child: Builder(builder: (context) {
        seen = ArxaKitGlassLuminance.maybeOf(context);
        return const SizedBox();
      }),
    )));

    expect(seen, isNotNull);
    expect(seen!.opaque, isFalse);
    expect(seen!.demotesGlass, isFalse,
        reason: 'a blurred glass surface is not the bright opaque base the '
            'washout remedy targets');
  });
}
