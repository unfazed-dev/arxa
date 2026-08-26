import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_native_switch.dart';

import 'arxa_kit_native_test_helpers.dart';

/// ArxaKitNativeSwitch is a **thin wrap** over [CNSwitch] with no M3E branch, so
/// these tests assert (a) it builds clean, (b) the Android kit gate is a no-op
/// for switches (still CNSwitch → Material fallback), and (c) onChanged fires.
///
/// CNSwitch embeds a real UiKitView on iOS/macOS 26+, which can't render in a
/// headless flutter_test. Every test below runs inside [withAndroidFallback],
/// which forces the widget-tree platform to Android so CNSwitch takes its
/// pure-Material `Switch` fallback — the only path reliably drivable here
/// (tap → onChanged). The kit branch (ArxaKitNativeSwitch → CNSwitch) is unchanged
/// on every platform; only the CN-internal render path is diverted.
void main() {
  tearDown(ArxaKitPlatform.reset);

  testWidgets('kit.ui-library.native-switch — builds clean', (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(const ArxaKitNativeSwitch(value: false)));

      expect(find.byType(ArxaKitNativeSwitch), findsOneWidget);
      expect(
        find.byType(Switch),
        findsOneWidget,
        reason: 'forced-Android CN fallback renders a Material Switch',
      );
    });
  });

  testWidgets(
      'kit.ui-library.native-switch — Android kit gate is a no-op (no M3E branch) and still builds',
      (tester) async {
    await withAndroidFallback(() async {
      // Switches have no M3E tier; forcing the kit gate to Android must NOT
      // change the render — still CNSwitch → Material Switch fallback.
      ArxaKitPlatform.override =
          const ArxaKitPlatformOverride(isAndroid: true);
      await tester.pumpWidget(host(const ArxaKitNativeSwitch(value: true)));

      expect(
        find.byType(Switch),
        findsOneWidget,
        reason: 'switch self-degrades to Material Switch even on Android',
      );
    });
  });

  testWidgets('kit.ui-library.native-switch — onChanged is wired',
      (tester) async {
    await withAndroidFallback(() async {
      bool? fired;
      await tester.pumpWidget(host(ArxaKitNativeSwitch(
        value: false,
        onChanged: (v) => fired = v,
      )));

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(fired, true, reason: 'tapping the switch must invoke onChanged');
    });
  });

  testWidgets(
      'kit.ui-library.native-switch — inside a scrollable keeps the native tier',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(const SingleChildScrollView(
        child: ArxaKitNativeSwitch(value: false),
      )));
      final cn = tester.widget<CNSwitch>(find.byType(CNSwitch));
      expect(
        cn.preferFlutterTier,
        isFalse,
        reason: 'a Scrollable ancestor must not demote the tier — the slab '
            'artifacts are compositional and law-gate-enforced away, so '
            'in-scroll controls stay native.',
      );
    });
  });

  testWidgets(
      'kit.ui-library.native-switch — outside a scrollable keeps the native tier',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(const ArxaKitNativeSwitch(value: false)));
      final cn = tester.widget<CNSwitch>(find.byType(CNSwitch));
      expect(
        cn.preferFlutterTier,
        isFalse,
        reason: 'no Scrollable ancestor → native platform view',
      );
    });
  });
}
