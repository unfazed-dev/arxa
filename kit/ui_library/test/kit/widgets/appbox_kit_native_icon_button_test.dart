import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart' show IconButtonM3E;
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_icon_button.dart';

import 'appbox_kit_native_test_helpers.dart';

/// Native-widget tests for [AppBoxKitNativeIconButton]. Two tiers:
///
/// - **M3E tier** (Android): the kit gate returns an [IconButtonM3E], a plain
///   widget — fully assertable via `find.byType(IconButtonM3E)`. THIS is the
///   load-bearing assertion.
/// - **Default tier**: the kit gate returns [CNButton.icon], which embeds a
///   real UiKitView on iOS/macOS 26+. A UiKitView can't render in a headless
///   flutter_test, so the default-tier test runs inside [withAndroidFallback]
///   to make CNButton take its pure-Material fallback.
void main() {
  tearDown(AppBoxKitPlatform.reset);

  testWidgets('kit.ui-library.native-icon-button — Android routes to IconButtonM3E', (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(host(const AppBoxKitNativeIconButton(icon: Icons.add)));

    expect(
      find.byType(IconButtonM3E),
      findsOneWidget,
      reason: 'supportsComposeM3E → kit must route to IconButtonM3E on Android',
    );
  });

  testWidgets('kit.ui-library.native-icon-button — default platform builds clean', (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(const AppBoxKitNativeIconButton(icon: Icons.add)));

      expect(
        find.byType(IconButtonM3E),
        findsNothing,
        reason: 'default platform is non-Android → kit must NOT route to M3E',
      );
    });
  });

  testWidgets('kit.ui-library.native-icon-button — onPressed is wired on the M3E tier', (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    var fired = false;
    await tester.pumpWidget(host(AppBoxKitNativeIconButton(
      icon: Icons.add,
      onPressed: () => fired = true,
    )));

    expect(find.byType(IconButtonM3E), findsOneWidget);
    await tester.tap(find.byType(IconButtonM3E));
    await tester.pumpAndSettle();

    expect(
      fired,
      isTrue,
      reason: 'tapping the icon button must invoke onPressed',
    );
  });
}
