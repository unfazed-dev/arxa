import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNPopupMenuButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_menu_item.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_native_popup_menu.dart';

import 'arxa_kit_native_test_helpers.dart';

/// Native-widget tests for [ArxaKitNativePopupMenu]. Two tiers:
///
/// - **M3E tier** (Android): the kit gate returns a Flutter Material [MenuAnchor]
///   (themed M3 Expressive motion). Assertable via `find.byType(MenuAnchor)`.
///   THIS is the load-bearing assertion.
/// - **CN tier** (default): the kit gate returns a [CNPopupMenuButton], which
///   embeds a real UiKitView on iOS/macOS 26+. A UiKitView can't render in a
///   headless flutter_test, so the CN-tier test runs inside
///   [withAndroidFallback].
void main() {
  tearDown(ArxaKitPlatform.reset);

  const items = [
    ArxaKitMenuItem(label: 'Rename', icon: Icons.edit),
    ArxaKitMenuItem(label: 'Archive', icon: Icons.archive_outlined),
    ArxaKitMenuItem(label: 'Delete', icon: Icons.delete, isDestructive: true),
  ];

  testWidgets(
      'kit.ui-library.native-popup-menu — Android opens a showMenu popup (same route as split button)',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(
      host(const ArxaKitNativePopupMenu(icon: Icons.more_vert, items: items)),
    );

    // No MenuAnchor — the M3E tier now opens Material's showMenu on tap (the
    // same route split_button_m3e uses, so the reveal motion matches).
    expect(find.byType(MenuAnchor), findsNothing);

    await tester.tap(find.byType(ArxaKitNativePopupMenu));
    await tester.pumpAndSettle();

    expect(
      find.byType(PopupMenuItem<ArxaKitMenuItem>),
      findsWidgets,
      reason: 'tapping the trigger opens a showMenu popup with the items',
    );
    expect(find.text('Rename'), findsOneWidget);
  });

  testWidgets(
      'kit.ui-library.native-popup-menu — default platform routes to CNPopupMenuButton (icon trigger)',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(
        host(const ArxaKitNativePopupMenu(
            icon: Icons.more_vert, items: items)),
      );

      expect(
        find.byType(CNPopupMenuButton),
        findsOneWidget,
        reason: 'default platform → kit must route to CNPopupMenuButton',
      );
    });
  });

  testWidgets(
      'kit.ui-library.native-popup-menu — default platform routes to CNPopupMenuButton (text trigger)',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(
        host(const ArxaKitNativePopupMenu(label: 'Actions', items: items)),
      );

      expect(
        find.byType(CNPopupMenuButton),
        findsOneWidget,
        reason: 'a label selects the text-trigger CN variant',
      );
    });
  });
}
