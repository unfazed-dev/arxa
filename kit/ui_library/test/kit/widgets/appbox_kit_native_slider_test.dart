import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNSlider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart' show SliderM3E;
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_slider.dart';

import 'appbox_kit_native_test_helpers.dart';

/// Canonical native-widget tests — they set the gate-routing pattern for the
/// rest of the kit. Two tiers matter:
///
/// - **M3E tier** (Android): the kit gate returns a [SliderM3E], a plain
///   widget — fully assertable via `find.byType(SliderM3E)`. THIS is the
///   load-bearing assertion.
/// - **CN tier** (default): the kit gate returns [CNSlider], which embeds a
///   real UiKitView on iOS/macOS 26+. A UiKitView can't render in a headless
///   flutter_test, so the CN-tier test runs inside [withAndroidFallback] to
///   make CNSlider take its pure-Material Slider fallback. The kit branch
///   (AppBoxKitNativeSlider → CNSlider) is unchanged — only the CN-internal render
///   path is diverted.
void main() {
  tearDown(AppBoxKitPlatform.reset);

  testWidgets('kit.ui-library.native-slider — Android routes to SliderM3E', (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(host(const AppBoxKitNativeSlider(value: 0.5)));

    expect(
      find.byType(SliderM3E),
      findsOneWidget,
      reason: 'supportsComposeM3E → kit must route to SliderM3E on Android',
    );
  });

  testWidgets('kit.ui-library.native-slider — default platform routes to CN (not SliderM3E) and builds clean',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(const AppBoxKitNativeSlider(value: 0.3)));

      expect(
        find.byType(SliderM3E),
        findsNothing,
        reason: 'default platform is non-Android → kit must NOT route to M3E',
      );
      expect(
        find.byType(Slider),
        findsOneWidget,
        reason: 'CNSlider Material fallback renders a Slider',
      );
    });
  });

  testWidgets('kit.ui-library.native-slider — onChanged is wired on the M3E tier', (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    double? fired;
    await tester.pumpWidget(host(AppBoxKitNativeSlider(
      value: 0.0,
      onChanged: (v) => fired = v,
    )));

    expect(find.byType(SliderM3E), findsOneWidget);
    // SliderM3E wraps a Material Slider; dragging the track moves it.
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(
      fired,
      isNotNull,
      reason: 'dragging the slider must invoke onChanged',
    );
  });

  testWidgets('kit.ui-library.native-slider — inside a scrollable demotes to the Flutter tier',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(const SingleChildScrollView(
        child: AppBoxKitNativeSlider(value: 0.5),
      )));
      final cn = tester.widget<CNSlider>(find.byType(CNSlider));
      expect(
        cn.preferFlutterTier,
        isTrue,
        reason: 'RULING REVERSED 2026-08-13 (docs/liquid-glass-allowlist.md '
            '§2, clip-0813 probe trail): in-scroll platform views slice later '
            'Flutter paint into clip-ignorant overlays (engine #150646) — '
            'in-scroll controls take the Flutter tier.',
      );
    });
  });

  testWidgets('kit.ui-library.native-slider — outside a scrollable keeps the native tier',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(const AppBoxKitNativeSlider(value: 0.5)));
      final cn = tester.widget<CNSlider>(find.byType(CNSlider));
      expect(
        cn.preferFlutterTier,
        isFalse,
        reason: 'no Scrollable ancestor → native platform view',
      );
    });
  });
}
