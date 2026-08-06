import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_chip.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_chip_carousel.dart';

import 'appbox_kit_native_test_helpers.dart';

/// AppBoxKitChipCarousel tests — rendering, the edge-fade invariant (fade only
/// when content overflows), scrolling, optional snap-to-chip settling, and
/// intrinsic height.
void main() {
  /// Fixed-size boxes with deterministic 100dp widths, so snap offsets are
  /// known exactly: with zero padding and 8dp spacing, chip i starts at
  /// i * 108.
  List<Widget> boxes(int count, {double width = 100}) => [
        for (var i = 0; i < count; i++)
          Container(
            key: ValueKey('box$i'),
            width: width,
            height: 36,
            color: Colors.grey,
          ),
      ];

  testWidgets('kit.ui-library.chip-carousel — renders all chips; no fade when everything fits',
      (tester) async {
    await tester.pumpWidget(host(const AppBoxKitChipCarousel(children: [
      AppBoxKitChip(label: 'One'),
      AppBoxKitChip(label: 'Two'),
      AppBoxKitChip(label: 'Three'),
    ])));
    await tester.pump();

    expect(find.text('One'), findsOneWidget);
    expect(find.text('Three'), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing,
        reason: 'edge fades draw only when content overflows');
  });

  testWidgets('kit.ui-library.chip-carousel — overflowing rail fades edges and scrolls to the last chip',
      (tester) async {
    await tester.pumpWidget(host(AppBoxKitChipCarousel(children: boxes(12))));
    await tester.pump(); // post-frame measure + fade setState

    expect(find.byType(ShaderMask), findsOneWidget,
        reason: '12 x 100dp chips overflow the 800dp test viewport');

    // The last chip starts off-screen to the right.
    expect(tester.getTopLeft(find.byKey(const ValueKey('box11'))).dx,
        greaterThanOrEqualTo(800));

    await tester.fling(
      find.byType(SingleChildScrollView),
      const Offset(-300, 0),
      10000,
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.byKey(const ValueKey('box11'))).dx,
        lessThan(800),
        reason: 'after scrolling, the last chip is inside the viewport');
    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('kit.ui-library.chip-carousel — snap settles on the nearest chip start', (tester) async {
    await tester.pumpWidget(host(AppBoxKitChipCarousel(
      snap: true,
      spacing: 8,
      padding: EdgeInsets.zero,
      children: boxes(10),
    )));
    await tester.pump(); // post-frame snap-offset measurement

    // Slow drag 150dp (between chip 1 at 108 and chip 2 at 216), released
    // with ~no velocity — the rail must spring back to 108, not park at 150.
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Row)));
    await gesture.moveBy(const Offset(-150, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.byKey(const ValueKey('box1'))).dx, 0.0,
        reason: 'settle target is the nearest chip start (108dp offset)');
  });

  testWidgets('kit.ui-library.chip-carousel — without snap, a slow drag parks where released', (tester) async {
    await tester.pumpWidget(host(AppBoxKitChipCarousel(
      spacing: 8,
      padding: EdgeInsets.zero,
      children: boxes(10),
    )));
    await tester.pump();

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Row)));
    await gesture.moveBy(const Offset(-150, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    // box1 starts at content offset 108, so at a 150dp scroll offset its
    // viewport x is 108 - 150 = -42.
    expect(tester.getTopLeft(find.byKey(const ValueKey('box1'))).dx, -42.0,
        reason: 'no snap → no corrective spring');
  });

  testWidgets('kit.ui-library.chip-carousel — chips stay tappable through the fade mask', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(AppBoxKitChipCarousel(children: [
      for (var i = 0; i < 12; i++)
        AppBoxKitChip(label: 'Chip $i', onTap: i == 0 ? () => taps++ : null),
    ])));
    await tester.pump();

    await tester.tap(find.text('Chip 0'));
    expect(taps, 1);
  });

  testWidgets('kit.ui-library.chip-carousel — rail height is intrinsic — tallest child wins', (tester) async {
    await tester.pumpWidget(host(const AppBoxKitChipCarousel(children: [
      AppBoxKitChip(label: 'Small'),
      SizedBox(height: 56, width: 80),
    ])));
    await tester.pump();

    expect(tester.getSize(find.byType(AppBoxKitChipCarousel)).height, 56.0,
        reason: 'no host-supplied height needed');
  });
}
