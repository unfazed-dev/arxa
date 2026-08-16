import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/common/appbox_kit_app_constants.dart';
import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_chip.dart';

import 'appbox_kit_native_test_helpers.dart';

/// AppBoxKitChip tests — label/glyph rendering, theming (stadium shape + container
/// tint), tap handling, and the minimum-height invariant.
void main() {
  testWidgets('kit.ui-library.chip — renders label + leading glyph',
      (tester) async {
    await tester.pumpWidget(host(const AppBoxKitChip(
      glyph: AppBoxKitGlyphs.camera,
      label: 'Photo',
    )));

    expect(find.text('Photo'), findsOneWidget);
    expect(find.byIcon(AppBoxKitGlyphs.camera.icon), findsOneWidget);
  });

  testWidgets('kit.ui-library.chip — text-only chip renders no icon',
      (tester) async {
    await tester.pumpWidget(host(const AppBoxKitChip(label: 'Plain')));

    expect(find.text('Plain'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('kit.ui-library.chip — tap fires onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(AppBoxKitChip(
      glyph: AppBoxKitGlyphs.mic,
      label: 'Voice',
      onTap: () => taps++,
    )));

    await tester.tap(find.byType(AppBoxKitChip));
    expect(taps, 1);
  });

  testWidgets(
      'kit.ui-library.chip — is a stadium pill tinted surfaceContainerHigh',
      (tester) async {
    await tester.pumpWidget(host(const AppBoxKitChip(label: 'Themed')));

    final material = tester.widget<Material>(find.descendant(
      of: find.byType(AppBoxKitChip),
      matching: find.byType(Material),
    ));
    expect(material.shape, isA<StadiumBorder>(),
        reason: 'a capability chip is a fully rounded pill');
    expect(material.color, ThemeData().colorScheme.surfaceContainerHigh,
        reason: 'the tint comes from the kit theme, not a hardcoded color');
  });

  testWidgets('kit.ui-library.chip — never shrinks below abxSize36',
      (tester) async {
    await tester.pumpWidget(host(const AppBoxKitChip(label: 'Height')));

    expect(
      tester.getSize(find.byType(AppBoxKitChip)).height,
      greaterThanOrEqualTo(abxSize36),
    );
  });
}
