import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_library/widgets/kit_frosted_surface.dart';

/// KitFrostedSurface tests — the ADR 0010 content-layer frosted tier:
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
      'renders the child behind a BackdropFilter, clipped to the '
      'rounded rect', (tester) async {
    await tester.pumpWidget(host(const KitFrostedSurface(
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

  testWidgets('tint + rim highlight ride the theme (light)', (tester) async {
    final light = ThemeData.light();
    // One theme per test: a second pumpWidget with a different MaterialApp
    // theme does not reliably re-propagate the inherited theme in
    // flutter_test, so the light/dark pair is split.
    await tester.pumpWidget(
        host(const KitFrostedSurface(child: Text('x')), theme: light));
    final deco = surfaceDecoration(tester);
    expect(deco.color,
        light.colorScheme.surfaceContainerLowest.withValues(alpha: 0.72),
        reason: 'light material = card token at 72%');
    expect((deco.border! as Border).top.color,
        Colors.white.withValues(alpha: 0.45));
  });

  testWidgets('tint + rim highlight ride the theme (dark)', (tester) async {
    final dark = ThemeData.dark();
    await tester.pumpWidget(
        host(const KitFrostedSurface(child: Text('x')), theme: dark));
    final deco = surfaceDecoration(tester);
    expect(deco.color,
        dark.colorScheme.surfaceContainerLowest.withValues(alpha: 0.55),
        reason: 'dark material = card token at 55%');
    expect((deco.border! as Border).top.color,
        Colors.white.withValues(alpha: 0.16));
  });

  testWidgets('tint override wins over the theme-derived default',
      (tester) async {
    await tester.pumpWidget(
        host(const KitFrostedSurface(tint: Colors.red, child: Text('x'))));
    expect(surfaceDecoration(tester).color, Colors.red);
  });
}
