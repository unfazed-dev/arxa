import 'package:cupertino_native_better/cupertino_native_better.dart'
    show LiquidGlassContainer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_glass_warmup.dart';

import 'arxa_kit_native_test_helpers.dart';

/// ArxaKitGlassWarmup tests — pins the two load-bearing mechanics: the warm
/// view is the card-kind [LiquidGlassContainer] translated off-screen per law
/// rule 8 (alpha/clip do NOT contain slicing geometry), and every non-glass
/// tier passes the child through with no warm view at all.
void main() {
  tearDown(ArxaKitPlatform.reset);

  testWidgets(
      'kit.ui-library.glass-warmup — iOS 26 mounts one rule-8-translated warm container',
      (tester) async {
    ArxaKitPlatform.override = const ArxaKitPlatformOverride(
      isIOS: true,
      iosMajor: 26,
    );
    await tester
        .pumpWidget(host(const ArxaKitGlassWarmup(child: Text('app'))));

    expect(find.text('app'), findsOneWidget,
        reason: 'the wrapped shell must still render');
    final container = find.byType(LiquidGlassContainer);
    expect(container, findsOneWidget,
        reason: 'warm view must construct the card-kind glass container — '
            'that is the pipeline the first pushed glass route hits');

    final transform = tester.widget<Transform>(
      find.ancestor(of: container, matching: find.byType(Transform)).first,
    );
    expect(
      transform.transform.getTranslation().x.abs(),
      greaterThanOrEqualTo(10000),
      reason: 'law rule 8: a hidden platform view feeds its UNCLIPPED rect to '
          'the view slicer — only off-screen translation contains it',
    );
    expect(
      find.ancestor(of: container, matching: find.byType(IgnorePointer)),
      findsWidgets,
      reason: 'the warm view must never hit-test',
    );
  });

  testWidgets(
      'kit.ui-library.glass-warmup — non-glass tier is a bare pass-through',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await tester
        .pumpWidget(host(const ArxaKitGlassWarmup(child: Text('app'))));

    expect(find.text('app'), findsOneWidget);
    expect(find.byType(LiquidGlassContainer), findsNothing,
        reason: 'no Liquid Glass support → nothing to warm, no extra tree');
  });
}
