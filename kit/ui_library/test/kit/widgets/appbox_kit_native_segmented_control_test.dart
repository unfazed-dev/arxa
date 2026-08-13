import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNSegmentedControl;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_segmented_control.dart';

import 'appbox_kit_native_test_helpers.dart';

/// Tier-split tests for [AppBoxKitNativeSegmentedControl] (mirrors
/// [appbox_kit_native_button_test]'s tier-split pattern). The CN tier is
/// reached via the iOS-26 kit override; [withAndroidFallback] diverts only the
/// CN-internal render path so no UiKitView is constructed headless.
void main() {
  tearDown(AppBoxKitPlatform.reset);

  Future<CNSegmentedControl> pumpCN(
    WidgetTester tester, {
    required bool inScrollable,
  }) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(
      isIOS: true,
      iosMajor: 26,
    );
    final control = AppBoxKitNativeSegmentedControl(
      segments: const ['One', 'Two'],
      selectedIndex: 0,
      onChanged: (_) {},
    );
    await tester.pumpWidget(host(
      inScrollable ? SingleChildScrollView(child: control) : control,
    ));
    return tester
        .widget<CNSegmentedControl>(find.byType(CNSegmentedControl));
  }

  testWidgets('kit.ui-library.native-segmented-control — inside a scrollable demotes to the Flutter tier',
      (tester) async {
    await withAndroidFallback(() async {
      final cn = await pumpCN(tester, inScrollable: true);
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

  testWidgets('kit.ui-library.native-segmented-control — outside a scrollable keeps the native tier',
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
