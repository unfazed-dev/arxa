import 'package:cupertino_native_better/cupertino_native_better.dart'
    show LiquidGlassContainer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_frosted_surface.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_glass_card.dart';

import 'appbox_kit_native_test_helpers.dart';

/// AppBoxKitGlassCard tests — the kit gate routes iOS 26 → [LiquidGlassContainer]
/// (a platform view that can't render headless, so the glass tier is asserted
/// only via the wantNative=false opt-out, never pumped directly) and everywhere
/// else → [AppBoxKitFrostedSurface], the Flutter-drawn frosted tier of ADR 0010
/// (occlusion-safe content-layer material). [AppBoxKitFrostedSurface] presence is
/// the load-bearing assertion.
void main() {
  tearDown(AppBoxKitPlatform.reset);

  testWidgets('kit.ui-library.glass-card — Android wantNative routes to the frosted tier, not glass',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(host(const AppBoxKitGlassCard(child: Text('card'))));

    expect(
      find.byType(AppBoxKitFrostedSurface),
      findsOneWidget,
      reason: 'non-iOS-26 → Flutter-drawn frosted tier (ADR 0010 tier split)',
    );
    expect(
      find.byType(LiquidGlassContainer),
      findsNothing,
      reason: 'Android tier must not construct a LiquidGlassContainer',
    );
  });

  testWidgets('kit.ui-library.glass-card — default tier builds clean and renders the child',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(const AppBoxKitGlassCard(child: Text('card'))));

      expect(
        find.byType(AppBoxKitFrostedSurface),
        findsOneWidget,
        reason: 'non-iOS-26 default → frosted tier',
      );
      expect(
        find.text('card'),
        findsOneWidget,
        reason: 'the host child must be rendered inside the card',
      );
    });
  });

  testWidgets('kit.ui-library.glass-card — wantNative=false opts out of glass even on iOS 26',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(
      isIOS: true,
      iosMajor: 26,
    );
    await tester.pumpWidget(
      host(const AppBoxKitGlassCard(wantNative: false, child: Text('card'))),
    );

    expect(
      find.byType(AppBoxKitFrostedSurface),
      findsOneWidget,
      reason: 'wantNative=false forces the Flutter-drawn frosted tier',
    );
    expect(
      find.byType(LiquidGlassContainer),
      findsNothing,
      reason: 'opt-out must skip the platform-view glass tier entirely',
    );
  });

  testWidgets('kit.ui-library.glass-card — inside a scrollable keeps the glass tier on iOS 26',
      (tester) async {
    // withAndroidFallback diverts only the CN-internal render path (the
    // container returns its child unchanged on non-Apple defaultTargetPlatform)
    // so the glass tier is safe to pump headless; the KIT gate still routes on
    // the iOS-26 override.
    await withAndroidFallback(() async {
      AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(
        isIOS: true,
        iosMajor: 26,
      );
      await tester.pumpWidget(host(const SingleChildScrollView(
        child: AppBoxKitGlassCard(child: Text('card')),
      )));

      expect(
        find.byType(LiquidGlassContainer),
        findsOneWidget,
        reason: 'a Scrollable ancestor must not demote the card — cards keep '
            'real glass everywhere the iOS 26 tier is available',
      );
      expect(
        find.byType(AppBoxKitFrostedSurface),
        findsNothing,
        reason: 'the glass tier must not double-paint the frosted fallback',
      );
    });
  });
}
