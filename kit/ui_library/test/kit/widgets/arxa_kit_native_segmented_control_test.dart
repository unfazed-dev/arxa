import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNSegmentedControl;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_native_segmented_control.dart';

import 'arxa_kit_native_test_helpers.dart';

/// Tier-split tests for [ArxaKitNativeSegmentedControl] (mirrors
/// [arxa_kit_native_button_test]'s tier-split pattern). The CN tier is
/// reached via the iOS-26 kit override; [withAndroidFallback] diverts only the
/// CN-internal render path so no UiKitView is constructed headless.
void main() {
  tearDown(ArxaKitPlatform.reset);

  Future<CNSegmentedControl> pumpCN(
    WidgetTester tester, {
    required bool inScrollable,
  }) async {
    ArxaKitPlatform.override = const ArxaKitPlatformOverride(
      isIOS: true,
      iosMajor: 26,
    );
    final control = ArxaKitNativeSegmentedControl(
      segments: const ['One', 'Two'],
      selectedIndex: 0,
      onChanged: (_) {},
    );
    await tester.pumpWidget(host(
      inScrollable ? SingleChildScrollView(child: control) : control,
    ));
    return tester.widget<CNSegmentedControl>(find.byType(CNSegmentedControl));
  }

  testWidgets(
      'kit.ui-library.native-segmented-control — stays native inside a scrollable',
      (tester) async {
    await withAndroidFallback(() async {
      final cn = await pumpCN(tester, inScrollable: true);
      expect(
        cn.preferFlutterTier,
        isFalse,
        reason: 'RULING 4 2026-08-13 (docs/liquid-glass-allowlist.md §2): all '
            'controls are native glass in scroll — the in-scroll auto-demotion '
            'is deleted kit-wide. If device artifacts return, re-demote per '
            'the widest-glass-first deselect ladder (segmented sits mid-list).',
      );
    });
  });

  testWidgets(
      'kit.ui-library.native-segmented-control — outside a scrollable keeps the native tier',
      (tester) async {
    await withAndroidFallback(() async {
      final cn = await pumpCN(tester, inScrollable: false);
      expect(
        cn.preferFlutterTier,
        isFalse,
        reason: 'no Scrollable ancestor → native platform view',
      );
    });
  });
}
