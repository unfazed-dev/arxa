import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_core/common/arxa_kit_app_constants.dart';
import 'package:arxa_kit_core/common/arxa_kit_glyphs.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_list_tile.dart';

import 'arxa_kit_native_test_helpers.dart';

/// ArxaKitListTile tests — the three row idioms (settings / menu / rich), the
/// trailing-slot precedence, tap handling, and the row-height invariant.
void main() {
  testWidgets(
      'kit.ui-library.list-tile — menu row: glyph + title render, no trailing chrome',
      (tester) async {
    await tester.pumpWidget(host(const ArxaKitListTile(
      glyph: ArxaKitGlyphs.settings,
      title: 'General',
    )));

    expect(find.text('General'), findsOneWidget);
    expect(find.byIcon(ArxaKitGlyphs.settings.icon), findsOneWidget);
    expect(find.byIcon(ArxaKitGlyphs.chevronRight.icon), findsNothing,
        reason: 'chevron is opt-in (showChevron), never default');
  });

  testWidgets(
      'kit.ui-library.list-tile — settings row: trailing value + chevron + tap',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(ArxaKitListTile(
      glyph: ArxaKitGlyphs.alerts,
      title: 'Notifications',
      trailingValue: 'On',
      showChevron: true,
      onTap: () => taps++,
    )));

    expect(find.text('On'), findsOneWidget);
    expect(find.byIcon(ArxaKitGlyphs.chevronRight.icon), findsOneWidget);

    await tester.tap(find.byType(ArxaKitListTile));
    expect(taps, 1);
  });

  testWidgets(
      'kit.ui-library.list-tile — rich row: subtitle + custom trailing replaces value/chevron',
      (tester) async {
    await tester.pumpWidget(host(const ArxaKitListTile(
      glyph: ArxaKitGlyphs.sheet,
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
    expect(find.byIcon(ArxaKitGlyphs.chevronRight.icon), findsNothing,
        reason: 'a custom trailing widget replaces the chevron');
  });

  testWidgets('kit.ui-library.list-tile — no glyph → no leading icon slot',
      (tester) async {
    await tester.pumpWidget(host(const ArxaKitListTile(title: 'Plain')));

    expect(find.byType(Icon), findsNothing);
    expect(find.text('Plain'), findsOneWidget);
  });

  testWidgets(
      'kit.ui-library.list-tile — row never shrinks below abxSize48, even one-line',
      (tester) async {
    await tester.pumpWidget(host(const ArxaKitListTile(title: 'Height')));

    final size = tester.getSize(find.byType(ArxaKitListTile));
    expect(size.height, greaterThanOrEqualTo(abxSize48));
  });

  testWidgets(
      'kit.ui-library.list-tile — null onTap renders the same visuals without crashing',
      (tester) async {
    await tester.pumpWidget(host(const ArxaKitListTile(
      glyph: ArxaKitGlyphs.info,
      title: 'About',
      trailingValue: '1.0',
    )));

    expect(find.text('About'), findsOneWidget);
    expect(find.text('1.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
