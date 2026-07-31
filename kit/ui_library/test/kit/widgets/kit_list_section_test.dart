import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/common/kit_glyphs.dart';
import 'package:ui_library/widgets/kit_glass_card.dart';
import 'package:ui_library/widgets/kit_list_section.dart';
import 'package:ui_library/widgets/kit_list_tile.dart';

import 'native_test_helpers.dart';

/// KitListSection tests — header, glass-card group container, divider
/// invariants, and row tap pass-through.
void main() {
  Widget section({
    String? header,
    bool showDividers = true,
    VoidCallback? onTap,
    int rows = 3,
  }) =>
      KitListSection(
        header: header,
        showDividers: showDividers,
        children: [
          for (var i = 0; i < rows; i++)
            KitListTile(
              glyph: KitGlyphs.settings,
              title: 'Row $i',
              showChevron: true,
              onTap: onTap,
            ),
        ],
      );

  testWidgets('renders the header above a glass-card group', (tester) async {
    await tester.pumpWidget(host(section(header: 'Account')));

    expect(find.text('Account'), findsOneWidget);
    expect(find.byType(KitGlassCard), findsOneWidget,
        reason: 'the group container is a KitGlassCard (no_raw_card_surface)');
    expect(find.text('Row 0'), findsOneWidget);
    expect(find.text('Row 2'), findsOneWidget);
  });

  testWidgets('no header when header is null', (tester) async {
    await tester.pumpWidget(host(section()));

    expect(find.text('Account'), findsNothing);
    expect(find.byType(KitGlassCard), findsOneWidget);
  });

  testWidgets('draws rows-1 dividers by default, none when disabled',
      (tester) async {
    await tester.pumpWidget(host(section(rows: 3)));
    expect(find.byType(Divider), findsNWidgets(2),
        reason: 'dividers sit between rows, never after the last');

    await tester.pumpWidget(host(section(rows: 3, showDividers: false)));
    expect(find.byType(Divider), findsNothing);

    await tester.pumpWidget(host(section(rows: 1)));
    expect(find.byType(Divider), findsNothing,
        reason: 'a single-row section has no divider');
  });

  testWidgets('row taps fire through the section', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(section(onTap: () => taps++)));

    await tester.tap(find.text('Row 1'));
    expect(taps, 1);
  });
}
