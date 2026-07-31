import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/common/kit_app_constants.dart';
import 'package:appbox_kit_core/common/kit_glyphs.dart';
import 'package:ui_library/widgets/kit_list_tile.dart';

import 'native_test_helpers.dart';

/// KitListTile tests — the three row idioms (settings / menu / rich), the
/// trailing-slot precedence, tap handling, and the row-height invariant.
void main() {
  testWidgets('menu row: glyph + title render, no trailing chrome',
      (tester) async {
    await tester.pumpWidget(host(const KitListTile(
      glyph: KitGlyphs.settings,
      title: 'General',
    )));

    expect(find.text('General'), findsOneWidget);
    expect(find.byIcon(KitGlyphs.settings.icon), findsOneWidget);
    expect(find.byIcon(KitGlyphs.chevronRight.icon), findsNothing,
        reason: 'chevron is opt-in (showChevron), never default');
  });

  testWidgets('settings row: trailing value + chevron + tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(KitListTile(
      glyph: KitGlyphs.alerts,
      title: 'Notifications',
      trailingValue: 'On',
      showChevron: true,
      onTap: () => taps++,
    )));

    expect(find.text('On'), findsOneWidget);
    expect(find.byIcon(KitGlyphs.chevronRight.icon), findsOneWidget);

    await tester.tap(find.byType(KitListTile));
    expect(taps, 1);
  });

  testWidgets('rich row: subtitle + custom trailing replaces value/chevron',
      (tester) async {
    await tester.pumpWidget(host(const KitListTile(
      glyph: KitGlyphs.sheet,
      title: 'Plugin',
      subtitle: 'v1.2 — enabled',
      trailingValue: 'SHOULD NOT RENDER',
      showChevron: true,
      trailing: Text('Manage'),
    )));

    expect(find.text('v1.2 — enabled'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('SHOULD NOT RENDER'), findsNothing,
        reason: 'a custom trailing widget replaces trailingValue');
    expect(find.byIcon(KitGlyphs.chevronRight.icon), findsNothing,
        reason: 'a custom trailing widget replaces the chevron');
  });

  testWidgets('no glyph → no leading icon slot', (tester) async {
    await tester.pumpWidget(host(const KitListTile(title: 'Plain')));

    expect(find.byType(Icon), findsNothing);
    expect(find.text('Plain'), findsOneWidget);
  });

  testWidgets('row never shrinks below kSize48, even one-line', (tester) async {
    await tester.pumpWidget(host(const KitListTile(title: 'Height')));

    final size = tester.getSize(find.byType(KitListTile));
    expect(size.height, greaterThanOrEqualTo(kSize48));
  });

  testWidgets('null onTap renders the same visuals without crashing',
      (tester) async {
    await tester.pumpWidget(host(const KitListTile(
      glyph: KitGlyphs.info,
      title: 'About',
      trailingValue: '1.0',
    )));

    expect(find.text('About'), findsOneWidget);
    expect(find.text('1.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
