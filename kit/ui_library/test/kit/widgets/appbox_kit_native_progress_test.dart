import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart'
    show CircularProgressIndicatorM3E, LinearProgressIndicatorM3E;
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_progress.dart';

import 'appbox_kit_native_test_helpers.dart';

/// Progress gate tests. The load-bearing assertion is `find.byType` on each M3E
/// class under the Android override. NOTE the circular dep class is named
/// `CircularProgressIndicatorM3E` (the *file* is circular_progress_m3e.dart —
/// the class name carries "Indicator"), hence the show-combinator above.
void main() {
  tearDown(AppBoxKitPlatform.reset);

  testWidgets('kit.ui-library.native-progress — Android .linear routes to LinearProgressIndicatorM3E',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(host(AppBoxKitNativeProgress.linear(value: 0.5)));

    expect(
      find.byType(LinearProgressIndicatorM3E),
      findsOneWidget,
      reason: 'supportsComposeM3E + linear → LinearProgressIndicatorM3E',
    );
  });

  testWidgets('kit.ui-library.native-progress — Android .circular routes to CircularProgressIndicatorM3E',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(host(AppBoxKitNativeProgress.circular()));

    expect(
      find.byType(CircularProgressIndicatorM3E),
      findsOneWidget,
      reason:
          'supportsComposeM3E + circular → CircularProgressIndicatorM3E '
          '(file circular_progress_m3e.dart, class carries "Indicator")',
    );
  });

  testWidgets('kit.ui-library.native-progress — default .linear builds clean (Material fallback)', (tester) async {
    await tester.pumpWidget(host(AppBoxKitNativeProgress.linear()));

    expect(find.byType(LinearProgressIndicatorM3E), findsNothing);
    expect(
      find.byType(LinearProgressIndicator),
      findsOneWidget,
      reason: 'non-Android linear → Material LinearProgressIndicator',
    );
  });

  testWidgets('kit.ui-library.native-progress — default .circular builds clean (indeterminate fallback)',
      (tester) async {
    await tester.pumpWidget(host(AppBoxKitNativeProgress.circular()));

    expect(
      find.byType(CircularProgressIndicatorM3E),
      findsNothing,
      reason: 'default platform must NOT route to M3E',
    );
  });
}
