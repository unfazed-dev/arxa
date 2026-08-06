import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNGlassButtonGroup;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart' show ToolbarM3E;
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_toolbar.dart';

import 'appbox_kit_native_test_helpers.dart';

/// Toolbar gate test — mirrors [kit_native_slider_test]. The load-bearing
/// assertion is the M3E-tier route: on Android (wantNative) the kit must surface
/// a [ToolbarM3E] whose `actions` are mapped 1:1 from [AppBoxKitToolbarAction]. The
/// default platform (macOS host) lands on the Material fallback row, which must
/// render each action's icon and wire its `onPressed`.
void main() {
  tearDown(AppBoxKitPlatform.reset);

  testWidgets('Android wantNative → ToolbarM3E', (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(host(AppBoxKitNativeToolbar(
      actions: [
        AppBoxKitToolbarAction(icon: Icons.add, onPressed: () {}),
        AppBoxKitToolbarAction(icon: Icons.delete, onPressed: () {}),
      ],
    )));

    expect(
      find.byType(ToolbarM3E),
      findsOneWidget,
      reason: 'supportsComposeM3E → kit must route to ToolbarM3E on Android',
    );
  });

  testWidgets('iOS glass tier pins button minHeight to height', (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isIOS: true);
    await withAndroidFallback(() async {
      // Material glyph (customIcon path) — same as the split button test — to
      // avoid CNIcon's PlatformViewGuard timer in widget tests.
      await tester.pumpWidget(host(AppBoxKitNativeToolbar(
        actions: [AppBoxKitToolbarAction(icon: Icons.add, onPressed: () {})],
      )));

      final group = tester
          .widget<CNGlassButtonGroup>(find.byType(CNGlassButtonGroup));
      expect(
        group.buttons.single.config.minHeight,
        44.0,
        reason: 'default height must match CNSearchBar expandedHeight (44)',
      );
    });
  });

  // ponytail: withAndroidFallback is belt-and-suspenders here — the macOS host
  // routes to the Material fallback (no CN widget is constructed), but wrapping
  // matches the kit's canonical native-widget test convention.
  testWidgets('default platform builds clean (Material fallback row)',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(AppBoxKitNativeToolbar(
        actions: [AppBoxKitToolbarAction(icon: Icons.add, onPressed: () {})],
      )));

      expect(
        find.byIcon(Icons.add),
        findsOneWidget,
        reason: 'fallback tier must render each action from its primitive icon',
      );
    });
  });

  testWidgets('action onPressed is wired on the fallback tier',
      (tester) async {
    var pressed = false;
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(AppBoxKitNativeToolbar(
        actions: [
          AppBoxKitToolbarAction(
            icon: Icons.add,
            onPressed: () => pressed = true,
          ),
        ],
      )));

      // The fallback tier renders an IconButton per icon-only action; tap it by
      // icon to prove the primitive's onPressed reached the rendered button.
      await tester.tap(find.byIcon(Icons.add));
      expect(pressed, isTrue, reason: 'action onPressed must fire on tap');
    });
  });
}
