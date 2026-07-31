import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/platform/kit_platform.dart';
import 'package:ui_library/widgets/kit_native_switch.dart';

import 'native_test_helpers.dart';

/// KitNativeSwitch is a **thin wrap** over [CNSwitch] with no M3E branch, so
/// these tests assert (a) it builds clean, (b) the Android kit gate is a no-op
/// for switches (still CNSwitch → Material fallback), and (c) onChanged fires.
///
/// CNSwitch embeds a real UiKitView on iOS/macOS 26+, which can't render in a
/// headless flutter_test. Every test below runs inside [withAndroidFallback],
/// which forces the widget-tree platform to Android so CNSwitch takes its
/// pure-Material `Switch` fallback — the only path reliably drivable here
/// (tap → onChanged). The kit branch (KitNativeSwitch → CNSwitch) is unchanged
/// on every platform; only the CN-internal render path is diverted.
void main() {
  tearDown(KitPlatform.reset);

  testWidgets('builds clean', (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(const KitNativeSwitch(value: false)));

      expect(find.byType(KitNativeSwitch), findsOneWidget);
      expect(
        find.byType(Switch),
        findsOneWidget,
        reason: 'forced-Android CN fallback renders a Material Switch',
      );
    });
  });

  testWidgets('Android kit gate is a no-op (no M3E branch) and still builds',
      (tester) async {
    await withAndroidFallback(() async {
      // Switches have no M3E tier; forcing the kit gate to Android must NOT
      // change the render — still CNSwitch → Material Switch fallback.
      KitPlatform.override = const KitPlatformOverride(isAndroid: true);
      await tester.pumpWidget(host(const KitNativeSwitch(value: true)));

      expect(
        find.byType(Switch),
        findsOneWidget,
        reason: 'switch self-degrades to Material Switch even on Android',
      );
    });
  });

  testWidgets('onChanged is wired', (tester) async {
    await withAndroidFallback(() async {
      bool? fired;
      await tester.pumpWidget(host(KitNativeSwitch(
        value: false,
        onChanged: (v) => fired = v,
      )));

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(fired, true, reason: 'tapping the switch must invoke onChanged');
    });
  });
}
