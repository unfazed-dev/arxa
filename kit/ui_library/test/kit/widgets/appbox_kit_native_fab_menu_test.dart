import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart' show FabMenuM3E;
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_menu_item.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_fab_menu.dart';

import 'appbox_kit_native_test_helpers.dart';

/// Native-widget tests for [AppBoxKitNativeFabMenu]. Two tiers:
///
/// - **M3E tier** (Android): the kit gate returns a [FabMenuM3E] — fully
///   assertable via `find.byType(FabMenuM3E)`. THIS is the load-bearing
///   assertion.
/// - **CN tier** (default): the kit gate returns a glass [CNPopupMenuButton],
///   which embeds a real UiKitView on iOS/macOS 26+. A UiKitView can't render
///   in a headless flutter_test, so the CN-tier test runs inside
///   [withAndroidFallback].
void main() {
  tearDown(AppBoxKitPlatform.reset);

  const items = [
    AppBoxKitMenuItem(label: 'Share', sfSymbol: 'square.and.arrow.up'),
    AppBoxKitMenuItem(label: 'Delete', sfSymbol: 'trash', isDestructive: true),
  ];

  testWidgets('kit.ui-library.native-fab-menu — Android routes to FabMenuM3E', (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(
      host(const AppBoxKitNativeFabMenu(icon: Icons.add, items: items)),
    );

    expect(
      find.byType(FabMenuM3E),
      findsOneWidget,
      reason: 'supportsComposeM3E → kit must route to FabMenuM3E on Android',
    );
  });

  testWidgets('kit.ui-library.native-fab-menu — default platform builds clean (CN glass tier)', (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(
        host(const AppBoxKitNativeFabMenu(icon: Icons.add, items: items)),
      );

      expect(
        find.byType(FabMenuM3E),
        findsNothing,
        reason: 'default platform is non-Android → kit must NOT route to M3E',
      );
    });
  });

  // M3E spec: the FAB Menu has no scrim (Compose FloatingActionButtonMenu is a
  // plain in-layout composable). The kit must pass overlay:false so fab_m3e's
  // default black α0.25 dimming never renders.
  testWidgets('kit.ui-library.native-fab-menu — M3E tier drops the scrim (overlay:false)', (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(
      host(const AppBoxKitNativeFabMenu(icon: Icons.add, items: items)),
    );

    final fab = tester.widget<FabMenuM3E>(find.byType(FabMenuM3E));
    expect(
      fab.overlay,
      isFalse,
      reason: 'M3E FAB Menu has no scrim — kit must pass overlay:false',
    );
  });

  // The signature M3E FAB-Menu morph: the primary FAB glyph flips Add → Close as
  // the menu opens (the FAB is the close affordance, since there is no scrim).
  testWidgets('kit.ui-library.native-fab-menu — primary FAB glyph morphs add → close on open', (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(
      host(const AppBoxKitNativeFabMenu(icon: Icons.add, items: items)),
    );

    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(
      find.byIcon(Icons.close),
      findsOneWidget,
      reason: 'open menu → FAB shows the close glyph (M3E Add↔Close morph)',
    );
    expect(find.byIcon(Icons.add), findsNothing);
  });
}
