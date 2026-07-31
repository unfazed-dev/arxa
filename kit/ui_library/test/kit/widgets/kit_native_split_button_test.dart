import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNGlassButtonGroup, CNSplitButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart' show SplitButtonM3E;
import 'package:appbox_kit_core/platform/kit_platform.dart';
import 'package:ui_library/widgets/kit_menu_item.dart';
import 'package:ui_library/widgets/kit_native_split_button.dart';

import 'native_test_helpers.dart';

/// Native-widget tests for [KitNativeSplitButton]. Three tiers:
///
/// - **M3E tier** (Android): the kit gate returns a [SplitButtonM3E] — fully
///   assertable via `find.byType(SplitButtonM3E)`. THIS is the load-bearing
///   assertion.
/// - **Glass tier** (iOS): the kit gate returns a [CNGlassButtonGroup], which
///   embeds a real UiKitView on iOS 26+. The test forces the gate to iOS via
///   [KitPlatformOverride] AND runs inside [withAndroidFallback] so the CN
///   widgets take their Flutter fallback (no UiKitView in a headless test).
/// - **Material tier** (else): the kit gate returns a [Row] + [PopupMenuButton].
void main() {
  tearDown(KitPlatform.reset);

  const menuItems = [
    KitMenuItem(label: 'Rename', icon: Icons.edit),
    KitMenuItem(label: 'Archive', icon: Icons.archive_outlined),
    KitMenuItem(label: 'Delete', icon: Icons.delete, isDestructive: true),
  ];

  testWidgets('Android routes to SplitButtonM3E', (tester) async {
    KitPlatform.override = const KitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(host(const KitNativeSplitButton(
      label: 'Save',
      icon: Icons.save,
      menuItems: menuItems,
    )));

    expect(
      find.byType(SplitButtonM3E<KitMenuItem>),
      findsOneWidget,
      reason: 'supportsComposeM3E → kit must route to SplitButtonM3E on Android',
    );
  });

  testWidgets('iOS routes to CNGlassButtonGroup and builds clean',
      (tester) async {
    KitPlatform.override = const KitPlatformOverride(isIOS: true);
    await withAndroidFallback(() async {
      // Icon-only action + Material chevron: a labeled action's icon+label Row
      // overflows the CN-internal Material fallback's shrink-wrapped width on
      // iOS < 26 (a cupertino_native_better fallback limitation; native iOS 26+
      // renders correctly). Material glyphs (customIcon) also avoid CNIcon's
      // 500ms PlatformViewGuard timer — the same reason KitNativeIconButton's
      // test passes a Material icon, not an SF Symbol.
      await tester.pumpWidget(host(const KitNativeSplitButton(
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
  // fallback must survive the KitMenuItem → CNButtonDataPopupItem mapping
  // (they used to be dropped on this tier).
  testWidgets('iOS tier maps destructive + Material fallback icon',
      (tester) async {
    KitPlatform.override = const KitPlatformOverride(isIOS: true);
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(const KitNativeSplitButton(
        icon: Icons.save,
        menuIcon: Icons.expand_more,
        menuItems: [
          KitMenuItem(label: 'Share', sfSymbol: 'square.and.arrow.up'),
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

  testWidgets('default (else) routes to Material PopupMenuButton',
      (tester) async {
    await tester.pumpWidget(host(const KitNativeSplitButton(
      label: 'Save',
      icon: Icons.save,
      menuItems: menuItems,
    )));

    expect(
      find.byType(SplitButtonM3E<KitMenuItem>),
      findsNothing,
      reason: 'non-Android, non-iOS → kit must NOT route to M3E',
    );
    expect(
      find.byType(CNGlassButtonGroup),
      findsNothing,
      reason: 'non-iOS → kit must NOT route to the glass group',
    );
    expect(
      find.byType(PopupMenuButton<KitMenuItem>),
      findsOneWidget,
      reason: 'else tier → kit must render a Material PopupMenuButton',
    );
  });
}
