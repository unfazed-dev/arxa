import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/common/appbox_kit_app_constants.dart';
import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_list_tile.dart';

import 'appbox_kit_native_test_helpers.dart';

/// AppBoxKitListTile tests — the three row idioms (settings / menu / rich), the
/// trailing-slot precedence, tap handling, and the row-height invariant.
void main() {
  testWidgets('kit.ui-library.list-tile — menu row: glyph + title render, no trailing chrome',
      (tester) async {
    await tester.pumpWidget(host(const AppBoxKitListTile(
      glyph: AppBoxKitGlyphs.settings,
      title: 'General',
    )));

    expect(find.text('General'), findsOneWidget);
    expect(find.byIcon(AppBoxKitGlyphs.settings.icon), findsOneWidget);
    expect(find.byIcon(AppBoxKitGlyphs.chevronRight.icon), findsNothing,
        reason: 'chevron is opt-in (showChevron), never default');
  });

  testWidgets('kit.ui-library.list-tile — settings row: trailing value + chevron + tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(AppBoxKitListTile(
      glyph: AppBoxKitGlyphs.alerts,
      title: 'Notifications',
      trailingValue: 'On',
      showChevron: true,
      onTap: () => taps++,
    )));

    expect(find.text('On'), findsOneWidget);
    expect(find.byIcon(AppBoxKitGlyphs.chevronRight.icon), findsOneWidget);

    await tester.tap(find.byType(AppBoxKitListTile));
    expect(taps, 1);
  });

  testWidgets('kit.ui-library.list-tile — rich row: subtitle + custom trailing replaces value/chevron',
      (tester) async {
    await tester.pumpWidget(host(const AppBoxKitListTile(
      glyph: AppBoxKitGlyphs.sheet,
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
    expect(find.byIcon(AppBoxKitGlyphs.chevronRight.icon), findsNothing,
        reason: 'a custom trailing widget replaces the chevron');
  });

  testWidgets('kit.ui-library.list-tile — no glyph → no leading icon slot', (tester) async {
    await tester.pumpWidget(host(const AppBoxKitListTile(title: 'Plain')));

    expect(find.byType(Icon), findsNothing);
    expect(find.text('Plain'), findsOneWidget);
  });

  testWidgets('kit.ui-library.list-tile — row never shrinks below axSize48, even one-line', (tester) async {
    await tester.pumpWidget(host(const AppBoxKitListTile(title: 'Height')));

    final size = tester.getSize(find.byType(AppBoxKitListTile));
    expect(size.height, greaterThanOrEqualTo(axSize48));
  });

  testWidgets('kit.ui-library.list-tile — null onTap renders the same visuals without crashing',
      (tester) async {
    await tester.pumpWidget(host(const AppBoxKitListTile(
      glyph: AppBoxKitGlyphs.info,
      title: 'About',
      trailingValue: '1.0',
    )));

    expect(find.text('About'), findsOneWidget);
    expect(find.text('1.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
