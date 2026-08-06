import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart'
    show ExtendedFabM3E, FabM3E;
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_fab_morph.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_fab.dart';

import 'appbox_kit_native_test_helpers.dart';

/// Native-widget tests for [AppBoxKitNativeFab]. Two tiers:
///
/// - **M3E tier** (Android): the kit gate returns a [FabM3E] (round) or
///   [ExtendedFabM3E] (when `label` is set) — fully assertable via
///   `find.byType`. THIS is the load-bearing assertion.
/// - **CN tier** (default): the kit gate returns a glass [CNButton], which
///   embeds a real UiKitView on iOS/macOS 26+. A UiKitView can't render in a
///   headless flutter_test, so the CN-tier test runs inside
///   [withAndroidFallback] to make CNButton take its pure-Material fallback.
void main() {
  tearDown(AppBoxKitPlatform.reset);

  // Round FAB routes to AppBoxKitFabMorph, NOT FabM3E: since the "consistent morphing"
  // change the round M3E FAB shape-morphs on press, and FabM3E's shape is static,
  // so the kit swaps in AppBoxKitFabMorph. Labeled still uses ExtendedFabM3E (below).
  testWidgets('kit.ui-library.native-fab — Android routes to AppBoxKitFabMorph (round, shape-morphs)',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(host(const AppBoxKitNativeFab(icon: Icons.add)));

    expect(
      find.byType(AppBoxKitFabMorph),
      findsOneWidget,
      reason: 'round M3E FAB morphs on press → kit routes to AppBoxKitFabMorph',
    );
    expect(
      find.byType(FabM3E),
      findsNothing,
      reason: 'FabM3E has a static shape — the round tier no longer uses it',
    );
    expect(
      find.byType(ExtendedFabM3E),
      findsNothing,
      reason: 'no label → must be the round FAB, not extended',
    );
  });

  testWidgets('kit.ui-library.native-fab — Android routes to ExtendedFabM3E when label is set',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(
      host(const AppBoxKitNativeFab(icon: Icons.add, label: 'Compose')),
    );

    expect(
      find.byType(ExtendedFabM3E),
      findsOneWidget,
      reason: 'label != null → kit must route to ExtendedFabM3E on Android',
    );
    expect(
      find.byType(FabM3E),
      findsNothing,
      reason: 'a label must select the extended FAB, not the round one',
    );
  });

  testWidgets('kit.ui-library.native-fab — default platform builds clean (CN glass tier)', (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(const AppBoxKitNativeFab(icon: Icons.add)));

      expect(
        find.byType(FabM3E),
        findsNothing,
        reason: 'default platform is non-Android → kit must NOT route to M3E',
      );
    });
  });
}
