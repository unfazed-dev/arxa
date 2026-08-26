import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart' show LoadingIndicatorM3E;
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_native_loading_indicator.dart';

import 'arxa_kit_native_test_helpers.dart';

/// Loading-indicator gate tests. Two tiers asserted:
///
/// - **M3E tier** (Android): kit routes to [LoadingIndicatorM3E] — the
///   load-bearing `find.byType` assertion.
/// - **default tier**: builds clean through the Material fallback. No CN widget
///   is mounted on any tier (CupertinoActivityIndicator / CircularProgressIndicator
///   are plain Flutter widgets), so [withAndroidFallback] is not needed here.
void main() {
  tearDown(ArxaKitPlatform.reset);

  testWidgets(
      'kit.ui-library.native-loading-indicator — Android routes to LoadingIndicatorM3E',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(
      host(const ArxaKitNativeLoadingIndicator(size: 32, color: Colors.blue)),
    );

    expect(
      find.byType(LoadingIndicatorM3E),
      findsOneWidget,
      reason:
          'supportsComposeM3E → kit must route to LoadingIndicatorM3E on Android',
    );
  });

  testWidgets(
      'kit.ui-library.native-loading-indicator — default platform builds clean (Material fallback)',
      (tester) async {
    await tester.pumpWidget(
      host(const ArxaKitNativeLoadingIndicator(size: 24, color: Colors.red)),
    );

    expect(
      find.byType(LoadingIndicatorM3E),
      findsNothing,
      reason: 'default platform is non-Android → kit must NOT route to M3E',
    );
    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason: 'non-Android / non-iOS default tier renders Material fallback',
    );
  });

  testWidgets(
      'kit.ui-library.native-loading-indicator — the Material fallback honors '
      'size: a tight clip, not the stock 36px default extent', (tester) async {
    await tester.pumpWidget(
      host(const ArxaKitNativeLoadingIndicator(size: 40, color: Colors.red)),
    );

    expect(
      tester.getSize(find.byType(CircularProgressIndicator)),
      const Size(40, 40),
      reason: 'the class contract pins every tier to the requested extent '
          '(M3E tight constraints, Cupertino radius, Material clip) — a bare '
          'indicator would cap at the stock 36px default',
    );
  });
}
