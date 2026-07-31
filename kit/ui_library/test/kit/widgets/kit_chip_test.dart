import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/common/kit_app_constants.dart';
import 'package:appbox_kit_core/common/kit_glyphs.dart';
import 'package:ui_library/widgets/kit_chip.dart';

import 'native_test_helpers.dart';

/// KitChip tests — label/glyph rendering, theming (stadium shape + container
/// tint), tap handling, and the minimum-height invariant.
void main() {
  testWidgets('renders label + leading glyph', (tester) async {
    await tester.pumpWidget(host(const KitChip(
      glyph: KitGlyphs.camera,
      label: 'Photo',
    )));

    expect(find.text('Photo'), findsOneWidget);
    expect(find.byIcon(KitGlyphs.camera.icon), findsOneWidget);
  });

  testWidgets('text-only chip renders no icon', (tester) async {
    await tester.pumpWidget(host(const KitChip(label: 'Plain')));

    expect(find.text('Plain'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('tap fires onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(KitChip(
      glyph: KitGlyphs.mic,
      label: 'Voice',
      onTap: () => taps++,
    )));

    await tester.tap(find.byType(KitChip));
    expect(taps, 1);
  });

  testWidgets('is a stadium pill tinted surfaceContainerHigh', (tester) async {
    await tester.pumpWidget(host(const KitChip(label: 'Themed')));

    final material = tester.widget<Material>(find.descendant(
      of: find.byType(KitChip),
      matching: find.byType(Material),
    ));
    expect(material.shape, isA<StadiumBorder>(),
        reason: 'a capability chip is a fully rounded pill');
    expect(material.color, ThemeData().colorScheme.surfaceContainerHigh,
        reason: 'the tint comes from the kit theme, not a hardcoded color');
  });

  testWidgets('never shrinks below kSize36', (tester) async {
    await tester.pumpWidget(host(const KitChip(label: 'Height')));

    expect(
      tester.getSize(find.byType(KitChip)).height,
      greaterThanOrEqualTo(kSize36),
    );
  });
}
