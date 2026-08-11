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

  testWidgets('kit.ui-library.native-toolbar — Android wantNative → ToolbarM3E', (tester) async {
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

  testWidgets('kit.ui-library.native-toolbar — iOS glass tier pins button minHeight to height', (tester) async {
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
  testWidgets('kit.ui-library.native-toolbar — default platform builds clean (Material fallback row)',
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

  testWidgets(
      'kit.ui-library.native-toolbar — three labelled actions do not overflow '
      'a phone-width fallback toolbar', (tester) async {
    // Device (2026-08-11): the profile showcase's toolbar demo — Share / Edit
    // / Delete — overflowed by 92px at 390pt. The fallback chose its layout
    // with `actions.length <= 4 ? Row : Wrap`, predicting fit from the COUNT
    // of actions when the constraint is width: a labelled action renders as a
    // FilledButton.tonal several times wider than an icon-only IconButton, so
    // three of them passed the `<= 4` test and then did not fit.
    tester.view.physicalSize = const Size(1170, 2532); // 390×844 logical
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await withAndroidFallback(() async {
      await tester.pumpWidget(host(AppBoxKitNativeToolbar(
        actions: [
          for (final label in const ['Share', 'Edit', 'Delete'])
            AppBoxKitToolbarAction(
                label: label, icon: Icons.add, onPressed: () {}),
        ],
      )));

      expect(find.text('Delete'), findsOneWidget,
          reason: 'anti-vacuous: the labelled actions must actually render, '
              'or an overflow could not occur either way');
      expect(tester.takeException(), isNull,
          reason: 'a RenderFlex overflow here means the layout still predicts '
              'fit from the action COUNT instead of laying out to the '
              'available width');
    });
  });

  testWidgets(
      'kit.ui-library.native-toolbar — mixed labelled/icon-only actions stay '
      'vertically centred on each other', (tester) async {
    // Pins the OUTCOME (a shared centre line), not the mechanism. Both action
    // shapes measure 48.0 tall today (FilledButton.tonal 144.5×48, IconButton
    // 48×48), so this passes under either Wrap alignment — removing
    // `crossAxisAlignment` does not fail it. That is deliberate: this is the
    // assertion that starts failing the day an action shape stops being 48,
    // which is exactly when the Row-to-Wrap swap could regress alignment.
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(AppBoxKitNativeToolbar(
        actions: [
          AppBoxKitToolbarAction(
              label: 'Share', icon: Icons.share, onPressed: () {}),
          AppBoxKitToolbarAction(icon: Icons.add, onPressed: () {}),
        ],
      )));

      expect(
        tester.getCenter(find.byType(FilledButton)).dy,
        closeTo(tester.getCenter(find.byType(IconButton)).dy, 0.5),
        reason: 'the two action shapes must share a centre line',
      );
    });
  });

  testWidgets('kit.ui-library.native-toolbar — action onPressed is wired on the fallback tier',
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
