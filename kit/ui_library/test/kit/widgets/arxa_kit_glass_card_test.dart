import 'package:cupertino_native_better/cupertino_native_better.dart'
    show LiquidGlassContainer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_frosted_surface.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_glass_card.dart';

import 'arxa_kit_native_test_helpers.dart';

/// ArxaKitGlassCard tests — the kit gate routes iOS 26 → [LiquidGlassContainer]
/// (a platform view that can't render headless, so the glass tier is asserted
/// only via the wantNative=false opt-out, never pumped directly) and everywhere
/// else → [ArxaKitFrostedSurface], the Flutter-drawn frosted tier of ADR 0010
/// (occlusion-safe content-layer material). [ArxaKitFrostedSurface] presence is
/// the load-bearing assertion.
void main() {
  tearDown(ArxaKitPlatform.reset);

  testWidgets(
      'kit.ui-library.glass-card — Android wantNative routes to the frosted tier, not glass',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await tester
        .pumpWidget(host(const ArxaKitGlassCard(child: Text('card'))));

    expect(
      find.byType(ArxaKitFrostedSurface),
      findsOneWidget,
      reason: 'non-iOS-26 → Flutter-drawn frosted tier (ADR 0010 tier split)',
    );
    expect(
      find.byType(LiquidGlassContainer),
      findsNothing,
      reason: 'Android tier must not construct a LiquidGlassContainer',
    );
  });

  testWidgets(
      'kit.ui-library.glass-card — default tier builds clean and renders the child',
      (tester) async {
    await withAndroidFallback(() async {
      await tester
          .pumpWidget(host(const ArxaKitGlassCard(child: Text('card'))));

      expect(
        find.byType(ArxaKitFrostedSurface),
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

  testWidgets(
      'kit.ui-library.glass-card — wantNative=false opts out of glass even on iOS 26',
      (tester) async {
    ArxaKitPlatform.override = const ArxaKitPlatformOverride(
      isIOS: true,
      iosMajor: 26,
    );
    await tester.pumpWidget(
      host(const ArxaKitGlassCard(wantNative: false, child: Text('card'))),
    );

    expect(
      find.byType(ArxaKitFrostedSurface),
      findsOneWidget,
      reason: 'wantNative=false forces the Flutter-drawn frosted tier',
    );
    expect(
      find.byType(LiquidGlassContainer),
      findsNothing,
      reason: 'opt-out must skip the platform-view glass tier entirely',
    );
  });

  testWidgets(
      'kit.ui-library.glass-card — inside a scrollable takes the frosted tier on iOS 26 (deselect ladder step 1)',
      (tester) async {
    // withAndroidFallback diverts only the CN-internal render path (the
    // container returns its child unchanged on non-Apple defaultTargetPlatform)
    // so the glass tier is safe to pump headless; the KIT gate still routes on
    // the iOS-26 override.
    await withAndroidFallback(() async {
      ArxaKitPlatform.override = const ArxaKitPlatformOverride(
        isIOS: true,
        iosMajor: 26,
      );
      await tester.pumpWidget(host(const SingleChildScrollView(
        child: ArxaKitGlassCard(child: Text('card')),
      )));

      expect(
        find.byType(LiquidGlassContainer),
        findsNothing,
        reason: 'in-scroll native glass is the jitter/flicker mechanism — '
            'the deselect ladder demotes the widest glass first',
      );
      expect(
        find.byType(ArxaKitFrostedSurface),
        findsOneWidget,
        reason: 'in-scroll cards render the Flutter-drawn frosted tier',
      );
    });
  });

  testWidgets(
      'kit.ui-library.glass-card — outside a scrollable keeps the glass tier on iOS 26',
      (tester) async {
    // The ladder demotes IN-SCROLL glass only: chrome and out-of-scroll
    // cards keep the native tier (ruling 4 stands for everything else).
    await withAndroidFallback(() async {
      ArxaKitPlatform.override = const ArxaKitPlatformOverride(
        isIOS: true,
        iosMajor: 26,
      );
      await tester.pumpWidget(
          host(const Center(child: ArxaKitGlassCard(child: Text('card')))));

      expect(
        find.byType(LiquidGlassContainer),
        findsOneWidget,
        reason: 'out-of-scroll cards keep real glass on the iOS 26 tier',
      );
    });
  });
}
