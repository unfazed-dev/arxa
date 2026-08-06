import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart' show NavigationRailM3E;
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_navigation_rail.dart';

import 'appbox_kit_native_test_helpers.dart';

/// Bars-tier gate test — mirrors [kit_native_slider_test]. The load-bearing
/// assertion is the M3E-tier route: on Android (wantNative) the kit must surface
/// a [NavigationRailM3E]. The default platform (macOS host) lands on a Material
/// [NavigationRail].
void main() {
  tearDown(AppBoxKitPlatform.reset);

  const destinations = [
    AppBoxKitRailDestination(icon: Icons.home, label: 'Home'),
    AppBoxKitRailDestination(icon: Icons.search, label: 'Search'),
  ];

  testWidgets('Android wantNative → NavigationRailM3E', (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(host(const AppBoxKitNativeNavigationRail(
      selectedIndex: 0,
      destinations: destinations,
    )));

    expect(
      find.byType(NavigationRailM3E),
      findsOneWidget,
      reason:
          'supportsComposeM3E → kit must route to NavigationRailM3E on Android',
    );
  });

  testWidgets('iOS extended → wide Cupertino rail with inline labels',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isIOS: true);
    await tester.pumpWidget(host(const AppBoxKitNativeNavigationRail(
      selectedIndex: 0,
      destinations: destinations,
      extended: true,
    )));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(AppBoxKitNativeNavigationRail)).width,
      220,
      reason: 'extended Cupertino rail widens to 220 (collapsed is 84)',
    );
    // Both width-pinned layers stay mounted (crossfaded) → label per layer.
    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('Android rail container is rounded (kit-side corner.large clip)',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(host(const AppBoxKitNativeNavigationRail(
      selectedIndex: 0,
      destinations: destinations,
    )));

    final clip = tester.widget<ClipRRect>(find.ancestor(
        of: find.byType(NavigationRailM3E), matching: find.byType(ClipRRect)));
    expect(
      clip.borderRadius,
      const BorderRadius.all(Radius.circular(16)),
      reason: 'kit rails float in cards — container clips to M3E corner.large',
    );
  });

  testWidgets('iOS built-in menu button toggles collapsed ↔ extended',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isIOS: true);
    await tester.pumpWidget(host(const AppBoxKitNativeNavigationRail(
      selectedIndex: 0,
      destinations: destinations,
    )));
    await tester.pumpAndSettle();

    // Parity with the M3E tier: the rail carries its own expand toggle.
    expect(find.byIcon(Icons.menu), findsOneWidget,
        reason: 'collapsed Cupertino rail shows a menu (expand) button');

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppBoxKitNativeNavigationRail)).width, 220,
        reason: 'menu button expands the rail');

    await tester.tap(find.byIcon(Icons.menu_open));
    // Mid-collapse the extended rows layer must still be fading (one shared
    // controller drives width + layer opacities — the reverse of expanding),
    // not vanish on frame 0.
    await tester.pump(const Duration(milliseconds: 100));
    final rowsLayer = tester
        .widgetList<FadeTransition>(find.byType(FadeTransition))
        .firstWhere(
            (f) => f.child is SizedBox && (f.child! as SizedBox).width == 220);
    expect(rowsLayer.opacity.value, greaterThan(0),
        reason: 'collapse fades the extended layout out during the shrink, '
            'no frame-0 snap');

    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppBoxKitNativeNavigationRail)).width, 84,
        reason: 'menu_open button collapses it back');
  });

  testWidgets('iOS collapsed → 84-wide Cupertino rail', (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isIOS: true);
    await tester.pumpWidget(host(const AppBoxKitNativeNavigationRail(
      selectedIndex: 0,
      destinations: destinations,
    )));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(AppBoxKitNativeNavigationRail)).width, 84);
  });

  testWidgets('default → Material NavigationRail, builds clean',
      (tester) async {
    await tester.pumpWidget(host(const AppBoxKitNativeNavigationRail(
      selectedIndex: 0,
      destinations: destinations,
    )));

    expect(
      find.byType(NavigationRail),
      findsOneWidget,
      reason: 'default platform → Material NavigationRail fallback',
    );
  });
}
