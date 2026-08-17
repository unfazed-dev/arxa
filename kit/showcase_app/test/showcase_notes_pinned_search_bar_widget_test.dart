import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_notes_widgets/showcase_notes_pinned_search_bar_widget.dart';

/// The pinned search header in the folder list. Its child is the native
/// Liquid Glass search bar (a UiKitView on iOS 26) — pinned sliver headers
/// count as chrome (docs/liquid-glass-allowlist.md class 1), so the bar
/// floats over the scrolling list as native glass. An opaque Flutter slab
/// behind it defeats the glass (nothing to sample) and reads as a hard cut
/// band across the scroll — the seam observed on device.
void main() {
  testWidgets(
      '[Search] — search-notes-by-text: the pinned header floats the glass bar over scrolling content (no opaque backing slab)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            ShowcaseNotesPinnedSearchBarWidget(
              child: SizedBox(height: 56),
            ),
          ],
        ),
      ),
    ));

    final header = find.byType(SliverPersistentHeader);
    expect(header, findsOneWidget);
    expect(tester.widget<SliverPersistentHeader>(header).pinned, isTrue,
        reason: 'the bar sticks under the app bar while the list scrolls');

    final opaqueSlab = find.descendant(
      of: header,
      matching: find.byWidgetPredicate((w) =>
          w is Material && w.color != null && w.color!.a == 1.0),
    );
    expect(opaqueSlab, findsNothing,
        reason: 'an opaque Flutter panel behind the translucent native glass '
            'bar is the visible cut band — iOS 26 floats search chrome over '
            'the content it samples');
  });
}
