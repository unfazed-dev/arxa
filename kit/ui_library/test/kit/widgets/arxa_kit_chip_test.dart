import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_core/common/arxa_kit_app_constants.dart';
import 'package:arxa_kit_core/common/arxa_kit_glyphs.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_chip.dart';

import 'arxa_kit_native_test_helpers.dart';

/// ArxaKitChip tests — label/glyph rendering, theming (stadium shape + container
/// tint), tap handling, and the minimum-height invariant.
void main() {
  testWidgets('kit.ui-library.chip — renders label + leading glyph',
      (tester) async {
    await tester.pumpWidget(host(const ArxaKitChip(
      glyph: ArxaKitGlyphs.camera,
      label: 'Photo',
    )));

    expect(find.text('Photo'), findsOneWidget);
    expect(find.byIcon(ArxaKitGlyphs.camera.icon), findsOneWidget);
  });

  testWidgets('kit.ui-library.chip — text-only chip renders no icon',
      (tester) async {
    await tester.pumpWidget(host(const ArxaKitChip(label: 'Plain')));

    expect(find.text('Plain'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('kit.ui-library.chip — tap fires onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(ArxaKitChip(
      glyph: ArxaKitGlyphs.mic,
      label: 'Voice',
      onTap: () => taps++,
    )));

    await tester.tap(find.byType(ArxaKitChip));
    expect(taps, 1);
  });

  testWidgets(
      'kit.ui-library.chip — is a stadium pill tinted surfaceContainerHigh',
      (tester) async {
    await tester.pumpWidget(host(const ArxaKitChip(label: 'Themed')));

    final material = tester.widget<Material>(find.descendant(
      of: find.byType(ArxaKitChip),
      matching: find.byType(Material),
    ));
    expect(material.shape, isA<StadiumBorder>(),
        reason: 'a capability chip is a fully rounded pill');
    expect(material.color, ThemeData().colorScheme.surfaceContainerHigh,
        reason: 'the tint comes from the kit theme, not a hardcoded color');
  });

  testWidgets('kit.ui-library.chip — never shrinks below abxSize36',
      (tester) async {
    await tester.pumpWidget(host(const ArxaKitChip(label: 'Height')));

    expect(
      tester.getSize(find.byType(ArxaKitChip)).height,
      greaterThanOrEqualTo(abxSize36),
    );
  });
}
