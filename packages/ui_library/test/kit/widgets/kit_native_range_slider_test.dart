import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart' show RangeSliderM3E;
import 'package:appbox_kit_core/platform/kit_platform.dart';
import 'package:ui_library/widgets/kit_native_range_slider.dart';

import 'native_test_helpers.dart';

/// Native-widget tests for [KitNativeRangeSlider]. Two tiers:
///
/// - **M3E tier** (Android): the kit gate returns a [RangeSliderM3E], a plain
///   widget — fully assertable via `find.byType(RangeSliderM3E)`. THIS is the
///   load-bearing assertion.
/// - **Default tier**: the kit gate returns Material's [RangeSlider] (there is
///   no `cupertino_native_better` range slider, so no UiKitView is involved).
///   Wrapped in [withAndroidFallback] to mirror the canonical pattern.
void main() {
  tearDown(KitPlatform.reset);

  testWidgets('Android routes to RangeSliderM3E', (tester) async {
    KitPlatform.override = const KitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(host(const KitNativeRangeSlider(
      values: RangeValues(0.2, 0.8),
    )));

    expect(
      find.byType(RangeSliderM3E),
      findsOneWidget,
      reason: 'supportsComposeM3E → kit must route to RangeSliderM3E on Android',
    );
  });

  testWidgets('default platform routes to Material RangeSlider and builds clean',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(const KitNativeRangeSlider(
        values: RangeValues(0.1, 0.4),
      )));

      expect(
        find.byType(RangeSliderM3E),
        findsNothing,
        reason: 'default platform is non-Android → kit must NOT route to M3E',
      );
      expect(
        find.byType(RangeSlider),
        findsOneWidget,
        reason: 'default tier renders a Material RangeSlider',
      );
    });
  });

  testWidgets('onChanged is wired on the M3E tier', (tester) async {
    KitPlatform.override = const KitPlatformOverride(isAndroid: true);
    RangeValues? fired;
    await tester.pumpWidget(host(KitNativeRangeSlider(
      values: const RangeValues(0.0, 0.5),
      onChanged: (v) => fired = v,
    )));

    expect(find.byType(RangeSliderM3E), findsOneWidget);
    // RangeSliderM3E wraps a Material RangeSlider; dragging the upper thumb
    // rightward moves it.
    await tester.drag(find.byType(RangeSlider), const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(
      fired,
      isNotNull,
      reason: 'dragging the range slider must invoke onChanged',
    );
  });
}
