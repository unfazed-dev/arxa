import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNButton, CNButtonStyle, CNSymbolRenderingMode;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_glass_luminance.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_button.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_icon_button.dart';

import 'appbox_kit_native_test_helpers.dart';

/// The global luminance adaptation: glass-styled native buttons demote to the
/// filled-gray idiom with on-surface monochrome ink on a bright OPAQUE base —
/// the remedy for the measured washout (glass labels on an opaque bright base,
/// iOS 26.5 simulator 2026-08-16) — applied automatically, never per call
/// site. Surfaces publish their luminance through [AppBoxKitGlassLuminance]
/// (AppBoxKitFrostedSurface's opaque branch, the opaque bar base, sheet and
/// dialog bodies); absent a declaration the theme's scaffold base decides.
void main() {
  tearDown(AppBoxKitPlatform.reset);

  setUp(() {
    // iOS 18 override: the vendor CNButton falls back to Cupertino headless
    // while the kit wrapper still takes the Apple branch, so the resolved
    // CNButtonConfig is assertable without a UiKitView.
    AppBoxKitPlatform.override =
        const AppBoxKitPlatformOverride(isIOS: true, iosMajor: 18);
  });

  CNButton cnButton(WidgetTester tester) =>
      tester.widget<CNButton>(find.byType(CNButton));

  Widget brightOpaqueScope(Widget child) => AppBoxKitGlassLuminance(
      opaque: true, brightness: Brightness.light, child: child);

  final onSurface = ThemeData.light().colorScheme.onSurface;

  testWidgets(
      'kit.ui-library.glass-luminance — a glass button on a bright opaque surface demotes to gray with on-surface monochrome ink',
      (tester) async {
    await tester.pumpWidget(host(brightOpaqueScope(AppBoxKitNativeButton(
      label: 'Continue',
      sfSymbol: 'star',
      onPressed: () {},
    ))));

    final cn = cnButton(tester);
    expect(cn.config.style, CNButtonStyle.gray,
        reason: 'glass washes out on a bright opaque base (measured '
            '2026-08-16); the filled-gray idiom is backdrop-independent');
    final symbol = cn.icon!;
    expect(symbol.mode, CNSymbolRenderingMode.monochrome);
    expect(symbol.color, onSurface,
        reason: 'primary-tinted glyphs read as decoration on the gray fill; '
            'the label ink is the neutral on-surface');
  });

  testWidgets(
      'kit.ui-library.glass-luminance — a glass button on a DARK opaque surface keeps its glass',
      (tester) async {
    await tester.pumpWidget(host(AppBoxKitGlassLuminance(
      opaque: true,
      brightness: Brightness.dark,
      child: AppBoxKitNativeButton(label: 'Continue', onPressed: () {}),
    )));

    expect(cnButton(tester).config.style, CNButtonStyle.glass,
        reason: 'the washout measurement was bright-base only; glass on dark '
            'opaque reads correctly');
  });

  testWidgets(
      'kit.ui-library.glass-luminance — a glass button on a translucent surface keeps its glass',
      (tester) async {
    await tester.pumpWidget(host(AppBoxKitGlassLuminance(
      opaque: false,
      brightness: Brightness.light,
      child: AppBoxKitNativeButton(label: 'Continue', onPressed: () {}),
    )));

    expect(cnButton(tester).config.style, CNButtonStyle.glass,
        reason: 'a blurred/translucent base is not the washout shape — the '
            'nearest declaration shadows the scaffold fallback');
  });

  testWidgets(
      'kit.ui-library.glass-luminance — absent a scope, a bright scaffold base demotes',
      (tester) async {
    await tester.pumpWidget(
        host(AppBoxKitNativeButton(label: 'Continue', onPressed: () {})));

    expect(cnButton(tester).config.style, CNButtonStyle.gray,
        reason: 'the default light scaffold IS a bright opaque base — the '
            'fallback makes the adaptation cover every surface, not just '
            'frosted ones');
  });

  testWidgets(
      'kit.ui-library.glass-luminance — absent a scope, a dark scaffold base keeps glass',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
          body: Center(
              child: AppBoxKitNativeButton(
                  label: 'Continue', onPressed: () {}))),
    ));

    expect(cnButton(tester).config.style, CNButtonStyle.glass);
  });

  testWidgets(
      'kit.ui-library.glass-luminance — luminanceAdaptive: false keeps glass on a bright base (escape hatch)',
      (tester) async {
    await tester.pumpWidget(host(brightOpaqueScope(AppBoxKitNativeButton(
      label: 'Continue',
      luminanceAdaptive: false,
      onPressed: () {},
    ))));

    expect(cnButton(tester).config.style, CNButtonStyle.glass,
        reason: 'a host that deliberately floats glass over bright imagery '
            'opts out per widget');
  });

  testWidgets(
      'kit.ui-library.glass-luminance — prominentGlass keeps its style on a bright base (the CTA stays prominent)',
      (tester) async {
    await tester.pumpWidget(host(brightOpaqueScope(AppBoxKitNativeButton(
      label: 'Sign In',
      style: AppBoxKitButtonStyle.prominentGlass,
      onPressed: () {},
    ))));

    expect(cnButton(tester).config.style, CNButtonStyle.prominentGlass,
        reason: 'the prominent CTA idiom is accent-filled and reads on '
            'bright bases; only the plain glass style washed out');
  });

  testWidgets(
      'kit.ui-library.glass-luminance — an icon button on a bright opaque surface demotes its capsule to gray',
      (tester) async {
    await tester.pumpWidget(host(brightOpaqueScope(
        AppBoxKitNativeIconButton(icon: Icons.add, onPressed: () {}))));

    expect(cnButton(tester).config.style, CNButtonStyle.gray,
        reason: 'the glass circle on a bright bar/sheet is the same washout '
            'class as the label button');
  });

  testWidgets(
      'kit.ui-library.glass-luminance — a plain icon button stays chromeless on a bright base',
      (tester) async {
    await tester.pumpWidget(host(brightOpaqueScope(AppBoxKitNativeIconButton(
        icon: Icons.close, plain: true, onPressed: () {}))));

    expect(cnButton(tester).config.style, CNButtonStyle.plain,
        reason: 'plain is chromeless by choice, not by luminance — no fill '
            'to wash out');
  });
}
