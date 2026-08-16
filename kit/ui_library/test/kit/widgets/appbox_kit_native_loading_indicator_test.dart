import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart' show LoadingIndicatorM3E;
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_loading_indicator.dart';

import 'appbox_kit_native_test_helpers.dart';

/// Loading-indicator gate tests. Two tiers asserted:
///
/// - **M3E tier** (Android): kit routes to [LoadingIndicatorM3E] — the
///   load-bearing `find.byType` assertion.
/// - **default tier**: builds clean through the Material fallback. No CN widget
///   is mounted on any tier (CupertinoActivityIndicator / CircularProgressIndicator
///   are plain Flutter widgets), so [withAndroidFallback] is not needed here.
void main() {
  tearDown(AppBoxKitPlatform.reset);

  testWidgets(
      'kit.ui-library.native-loading-indicator — Android routes to LoadingIndicatorM3E',
      (tester) async {
    AppBoxKitPlatform.override =
        const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(
      host(const AppBoxKitNativeLoadingIndicator(size: 32, color: Colors.blue)),
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
      host(const AppBoxKitNativeLoadingIndicator(size: 24, color: Colors.red)),
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
}
