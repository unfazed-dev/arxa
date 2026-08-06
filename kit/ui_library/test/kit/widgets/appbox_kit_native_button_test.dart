import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNButton, CNButtonStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart'
    show ButtonM3E, ButtonM3EStyle;
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_button.dart';

import 'appbox_kit_native_test_helpers.dart';

/// Native-widget tests for [AppBoxKitNativeButton]. Two tiers:
///
/// - **M3E tier** (Android): the kit gate returns a [ButtonM3E] — fully
///   assertable via `find.byType(ButtonM3E)`, including the *emphasis map*
///   (kit style → ButtonM3EStyle), which is the load-bearing contract: a
///   secondary iOS style (e.g. `plain`) must never render as a second filled
///   primary CTA on Android.
/// - **Default tier**: the kit gate returns [CNButton], which embeds a real
///   UiKitView on iOS/macOS 26+. A UiKitView can't render in a headless
///   flutter_test, so the default-tier test runs inside [withAndroidFallback]
///   to make CNButton take its pure-Material fallback.
void main() {
  tearDown(AppBoxKitPlatform.reset);

  Future<ButtonM3E> pumpM3E(WidgetTester tester, AppBoxKitButtonStyle style) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(host(AppBoxKitNativeButton(
      label: 'Go',
      style: style,
      onPressed: () {},
    )));
    expect(find.byType(ButtonM3E), findsOneWidget);
    return tester.widget<ButtonM3E>(find.byType(ButtonM3E));
  }

  testWidgets('kit.ui-library.native-button — Android routes to ButtonM3E', (tester) async {
    await pumpM3E(tester, AppBoxKitButtonStyle.glass);
  });

  testWidgets('kit.ui-library.native-button — emphasis map: plain → text (never a filled CTA)',
      (tester) async {
    final button = await pumpM3E(tester, AppBoxKitButtonStyle.plain);
    expect(
      button.style,
      ButtonM3EStyle.text,
      reason: 'plain is Apple\'s text-only style — its M3E peer is the text '
          'button, NOT the filled default (which would duplicate the primary '
          'CTA, e.g. auth\'s Create Account next to Sign In)',
    );
  });

  testWidgets('kit.ui-library.native-button — emphasis map: high-emphasis styles → filled', (tester) async {
    for (final style in [
      AppBoxKitButtonStyle.prominentGlass,
      AppBoxKitButtonStyle.filled,
      AppBoxKitButtonStyle.borderedProminent,
    ]) {
      final button = await pumpM3E(tester, style);
      expect(button.style, ButtonM3EStyle.filled,
          reason: '$style is high-emphasis → M3E filled');
    }
  });

  testWidgets('kit.ui-library.native-button — emphasis map: mid-emphasis surfaces → tonal', (tester) async {
    for (final style in [
      AppBoxKitButtonStyle.glass,
      AppBoxKitButtonStyle.gray,
      AppBoxKitButtonStyle.tinted,
    ]) {
      final button = await pumpM3E(tester, style);
      expect(button.style, ButtonM3EStyle.tonal,
          reason: '$style is mid-emphasis → M3E tonal');
    }
  });

  testWidgets('kit.ui-library.native-button — emphasis map: bordered → outlined', (tester) async {
    final button = await pumpM3E(tester, AppBoxKitButtonStyle.bordered);
    expect(button.style, ButtonM3EStyle.outlined);
  });

  testWidgets('kit.ui-library.native-button — default platform builds clean (no M3E)', (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(AppBoxKitNativeButton(
        label: 'Go',
        onPressed: () {},
      )));
      expect(
        find.byType(ButtonM3E),
        findsNothing,
        reason: 'default platform is non-Android → kit must NOT route to M3E',
      );
    });
  });

  testWidgets('kit.ui-library.native-button — CN tier (Liquid Glass) passes every kit style through 1:1',
      (tester) async {
    await withAndroidFallback(() async {
      for (final style in AppBoxKitButtonStyle.values) {
        await tester.pumpWidget(host(AppBoxKitNativeButton(
          label: 'Go',
          style: style,
          onPressed: () {},
        )));
        final cn = tester.widget<CNButton>(find.byType(CNButton));
        expect(
          cn.config.style,
          CNButtonStyle.values.byName(style.name),
          reason: 'AppBoxKitButtonStyle is a 1:1 name mirror of CNButtonStyle and '
              'the kit resolves it via values.byName — if the enums drift '
              '(rename/removal on either side), byName throws at RUNTIME on '
              'the Apple tier. ${style.name} must resolve.',
        );
      }
    });
  });

  testWidgets('kit.ui-library.native-button — onPressed is wired on the M3E tier', (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    var fired = false;
    await tester.pumpWidget(host(AppBoxKitNativeButton(
      label: 'Go',
      onPressed: () => fired = true,
    )));

    expect(find.byType(ButtonM3E), findsOneWidget);
    await tester.tap(find.byType(ButtonM3E));
    await tester.pumpAndSettle();

    expect(fired, isTrue, reason: 'tapping the button must invoke onPressed');
  });
}
