import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNButton, CNButtonConfig, CNButtonStyle;
import 'package:flutter/cupertino.dart' show CupertinoButton;
import 'package:flutter/widgets.dart' show SingleChildScrollView;
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

  testWidgets(
      'kit.ui-library.native-button — inside a scrollable stays native and '
      'glass styles pass through unmapped', (tester) async {
    await withAndroidFallback(() async {
      for (final style in [
        AppBoxKitButtonStyle.glass,
        AppBoxKitButtonStyle.prominentGlass,
      ]) {
        await tester.pumpWidget(host(SingleChildScrollView(
          child: AppBoxKitNativeButton(
            label: 'Go',
            style: style,
            onPressed: () {},
          ),
        )));
        final cn = tester.widget<CNButton>(find.byType(CNButton));
        expect(
          cn.config.style,
          CNButtonStyle.values.byName(style.name),
          reason: 'INFORMED ALLOWLIST 2026-08-13 (docs/liquid-glass-allowlist '
              '.md §2): button-class controls are exposure-safe in scroll '
              '(home ran 7 native in-scroll CNButton views clean) — glass '
              'styles pass through 1:1, no in-scroll remap.',
        );
        expect(
          cn.config.preferFlutterTier,
          isFalse,
          reason: 'in-scroll buttons stay native platform views — since '
              'ruling 4 (2026-08-13) no control auto-demotes in scroll.',
        );
      }
    });
  });

  testWidgets(
      'kit.ui-library.native-button — outside a scrollable glass styles pass '
      'through unchanged', (tester) async {
    await withAndroidFallback(() async {
      for (final style in [
        AppBoxKitButtonStyle.glass,
        AppBoxKitButtonStyle.prominentGlass,
      ]) {
        await tester.pumpWidget(host(AppBoxKitNativeButton(
          label: 'Go',
          style: style,
          onPressed: () {},
        )));
        final cn = tester.widget<CNButton>(find.byType(CNButton));
        expect(
          cn.config.style,
          CNButtonStyle.values.byName(style.name),
          reason: 'no Scrollable ancestor → the glass styles are in contract '
              '(docs/liquid-glass-allowlist.md §2) and must not be remapped',
        );
      }
    });
  });

  testWidgets(
      'kit.ui-library.native-button — CN pre-26 fallback: solid styles keep a '
      'visible label (foreground contrasts with fill)', (tester) async {
    // Exercises CNButton's own Flutter-tier fallback directly (the pre-26
    // Cupertino tier + vendor PATCH #5): preferFlutterTier forces the
    // CupertinoButton path, where a solid fill must carry an explicit
    // contrasting foreground.
    await withCupertinoFallback(() async {
      for (final style in [
        CNButtonStyle.prominentGlass,
        CNButtonStyle.filled,
        CNButtonStyle.borderedProminent,
      ]) {
        await tester.pumpWidget(host(CNButton(
          label: 'Sign In',
          onPressed: () {},
          config: CNButtonConfig(
            preferFlutterTier: true,
            style: style,
          ),
        )));
        final button =
            tester.widget<CupertinoButton>(find.byType(CupertinoButton));
        expect(
          button.foregroundColor,
          isNotNull,
          reason: '$style falls back to a CupertinoButton with a solid tint '
              'fill; the plain-style default foreground is primaryColor — the '
              'SAME color as the fill — which rendered auth\'s Sign In as a '
              'blank purple capsule. The fallback must pass an explicit '
              'contrasting foreground (vendor PATCH #5).',
        );
        expect(button.foregroundColor, isNot(equals(button.color)),
            reason: 'label color must differ from the fill it sits on');
      }
    });
  });

  testWidgets(
      'kit.ui-library.native-button — CN pre-26 fallback: glass style keeps a '
      'visible label (tint foreground on the translucent tint fill)',
      (tester) async {
    // Glass falls back to a TRANSLUCENT tint fill (tint at 10% alpha), and
    // CupertinoButton's default foreground whenever `color` is non-null is
    // primaryContrastingColor — white on a 10% wash over a light background
    // is invisible (the profile toolbar's blank Share/Edit/Delete labels on
    // device, 2026-08-12). Apple's pre-26 tinted look is
    // tint-on-translucent-tint, so the fallback must pass the tint through
    // as the foreground.
    await withCupertinoFallback(() async {
      await tester.pumpWidget(host(CNButton(
        label: 'Share',
        onPressed: () {},
        config: const CNButtonConfig(
          preferFlutterTier: true,
          style: CNButtonStyle.glass,
        ),
      )));
      final button =
          tester.widget<CupertinoButton>(find.byType(CupertinoButton));
      expect(button.foregroundColor, isNotNull,
          reason: 'glass fallback sets a translucent fill, which flips the '
              'CupertinoButton default foreground to primaryContrastingColor '
              '— invisible over the wash; the tint must be passed explicitly');
      expect(button.foregroundColor, isNot(equals(button.color)),
          reason: 'label color must differ from the fill it sits on');
      expect(button.foregroundColor!.a, 1.0,
          reason: 'the label carries the full-alpha tint, not the 10% wash');
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
