import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNGlassButtonGroup, CNSplitButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart' show SplitButtonM3E;
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_menu_item.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_split_button.dart';

import 'appbox_kit_native_test_helpers.dart';

/// Native-widget tests for [AppBoxKitNativeSplitButton]. Three tiers:
///
/// - **M3E tier** (Android): the kit gate returns a [SplitButtonM3E] — fully
///   assertable via `find.byType(SplitButtonM3E)`. THIS is the load-bearing
///   assertion.
/// - **Glass tier** (iOS): the kit gate returns a [CNGlassButtonGroup], which
///   embeds a real UiKitView on iOS 26+. The test forces the gate to iOS via
///   [AppBoxKitPlatformOverride] AND runs inside [withAndroidFallback] so the CN
///   widgets take their Flutter fallback (no UiKitView in a headless test).
/// - **Material tier** (else): the kit gate returns a [Row] + [PopupMenuButton].
void main() {
  tearDown(AppBoxKitPlatform.reset);

  const menuItems = [
    AppBoxKitMenuItem(label: 'Rename', icon: Icons.edit),
    AppBoxKitMenuItem(label: 'Archive', icon: Icons.archive_outlined),
    AppBoxKitMenuItem(label: 'Delete', icon: Icons.delete, isDestructive: true),
  ];

  testWidgets('kit.ui-library.native-split-button — Android routes to SplitButtonM3E', (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(host(const AppBoxKitNativeSplitButton(
      label: 'Save',
      icon: Icons.save,
      menuItems: menuItems,
    )));

    expect(
      find.byType(SplitButtonM3E<AppBoxKitMenuItem>),
      findsOneWidget,
      reason: 'supportsComposeM3E → kit must route to SplitButtonM3E on Android',
    );
  });

  testWidgets('kit.ui-library.native-split-button — iOS routes to CNGlassButtonGroup and builds clean',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isIOS: true);
    await withAndroidFallback(() async {
      // Icon-only action + Material chevron: a labeled action's icon+label Row
      // overflows the CN-internal Material fallback's shrink-wrapped width on
      // iOS < 26 (a cupertino_native_better fallback limitation; native iOS 26+
      // renders correctly). Material glyphs (customIcon) also avoid CNIcon's
      // 500ms PlatformViewGuard timer — the same reason AppBoxKitNativeIconButton's
      // test passes a Material icon, not an SF Symbol.
      await tester.pumpWidget(host(const AppBoxKitNativeSplitButton(
        icon: Icons.save,
        menuIcon: Icons.expand_more,
        menuItems: menuItems,
      )));

      expect(
        find.byType(CNGlassButtonGroup),
        findsOneWidget,
        reason: 'iOS → kit must route to CNGlassButtonGroup',
      );
    });
  });

  // Menu parity with the appbar/FAB menu: destructive + Material-icon
  // fallback must survive the AppBoxKitMenuItem → CNButtonDataPopupItem mapping
  // (they used to be dropped on this tier).
  testWidgets('kit.ui-library.native-split-button — iOS tier maps destructive + Material fallback icon',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isIOS: true);
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(const AppBoxKitNativeSplitButton(
        icon: Icons.save,
        menuIcon: Icons.expand_more,
        menuItems: [
          AppBoxKitMenuItem(label: 'Share', sfSymbol: 'square.and.arrow.up'),
          ...menuItems, // Rename/Archive (icon-only) + destructive Delete
        ],
      )));

      final split = tester.widget<CNSplitButton>(find.byType(CNSplitButton));
      expect(split.items, hasLength(4));

      expect(split.items[0].sfSymbol, 'square.and.arrow.up');
      expect(split.items[0].customIcon, isNull,
          reason: 'SF Symbol wins — no Material fallback alongside it');

      expect(split.items[1].sfSymbol, isNull);
      expect(split.items[1].customIcon, Icons.edit,
          reason: 'no SF Symbol → the Material icon must survive the mapping');

      expect(split.items[3].isDestructive, isTrue,
          reason: 'destructive must reach the native menu (red item)');
    });
  });

  testWidgets('kit.ui-library.native-split-button — default (else) routes to Material PopupMenuButton',
      (tester) async {
    await tester.pumpWidget(host(const AppBoxKitNativeSplitButton(
      label: 'Save',
      icon: Icons.save,
      menuItems: menuItems,
    )));

    expect(
      find.byType(SplitButtonM3E<AppBoxKitMenuItem>),
      findsNothing,
      reason: 'non-Android, non-iOS → kit must NOT route to M3E',
    );
    expect(
      find.byType(CNGlassButtonGroup),
      findsNothing,
      reason: 'non-iOS → kit must NOT route to the glass group',
    );
    expect(
      find.byType(PopupMenuButton<AppBoxKitMenuItem>),
      findsOneWidget,
      reason: 'else tier → kit must render a Material PopupMenuButton',
    );
  });
}
