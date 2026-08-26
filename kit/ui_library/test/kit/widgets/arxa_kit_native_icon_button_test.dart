import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNButton, CNButtonStyle;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart' show IconButtonM3E;
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_native_icon_button.dart';

import 'arxa_kit_native_test_helpers.dart';

/// Native-widget tests for [ArxaKitNativeIconButton]. Two tiers:
///
/// - **M3E tier** (Android): the kit gate returns an [IconButtonM3E], a plain
///   widget — fully assertable via `find.byType(IconButtonM3E)`. THIS is the
///   load-bearing assertion.
/// - **Default tier**: the kit gate returns [CNButton.icon], which embeds a
///   real UiKitView on iOS/macOS 26+. A UiKitView can't render in a headless
///   flutter_test, so the default-tier test runs inside [withAndroidFallback]
///   to make CNButton take its pure-Material fallback.
void main() {
  tearDown(ArxaKitPlatform.reset);

  testWidgets(
      'kit.ui-library.native-icon-button — Android routes to IconButtonM3E',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await tester
        .pumpWidget(host(const ArxaKitNativeIconButton(icon: Icons.add)));

    expect(
      find.byType(IconButtonM3E),
      findsOneWidget,
      reason: 'supportsComposeM3E → kit must route to IconButtonM3E on Android',
    );
  });

  testWidgets(
      'kit.ui-library.native-icon-button — default platform builds clean',
      (tester) async {
    await withAndroidFallback(() async {
      await tester
          .pumpWidget(host(const ArxaKitNativeIconButton(icon: Icons.add)));

      expect(
        find.byType(IconButtonM3E),
        findsNothing,
        reason: 'default platform is non-Android → kit must NOT route to M3E',
      );
    });
  });

  testWidgets(
      'kit.ui-library.native-icon-button — onPressed is wired on the M3E tier',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    var fired = false;
    await tester.pumpWidget(host(ArxaKitNativeIconButton(
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

  // CNButton icon priority is imageAsset > customIcon > icon (button.dart:207),
  // so an always-set customIcon shadows the native SF Symbol path and forces
  // the raster branch. The guard is asserted at the CNButton boundary: those
  // constructor args deterministically select the platform-view creationParams
  // branch, and a real UiKitView can't be constructed in a headless
  // flutter_test (see [withAndroidFallback]).
  testWidgets(
      'kit.ui-library.native-icon-button — SF Symbol input must NOT pass customIcon',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(const ArxaKitNativeIconButton(
        icon: Icons.add,
        sfSymbol: 'plus',
      )));

      final cn = tester.widget<CNButton>(find.byType(CNButton));
      expect(
        cn.icon?.name,
        'plus',
        reason:
            'SF-symbol-capable input must ride CNButton\'s native symbol path',
      );
      expect(
        cn.customIcon,
        isNull,
        reason: 'customIcon shadows the SF Symbol (priority imageAsset > '
            'customIcon > icon) — it must be withheld when a symbol exists',
      );
    });
  });

  testWidgets(
      'kit.ui-library.native-icon-button — icon without SF Symbol still passes customIcon',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(const ArxaKitNativeIconButton(
        icon: Icons.add,
      )));

      final cn = tester.widget<CNButton>(find.byType(CNButton));
      expect(cn.icon, isNull);
      expect(
        cn.customIcon,
        Icons.add,
        reason: 'with no SF Symbol equivalent the rasterized Material glyph is '
            'the only Apple-tier rendering — customIcon must still be passed',
      );
    });
  });

  // Chromeless variant: inline glyph actions (a chip's remove control, a
  // dense row action) must not carry the glass capsule — the outlined
  // circle reads as a button INSIDE a button. Plain routes CNButtonStyle.plain
  // on the Apple tier; the M3E tier is already chromeless at rest.
  testWidgets(
      'kit.ui-library.native-icon-button — plain requests the chromeless Apple-tier style',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(host(const ArxaKitNativeIconButton(
        icon: Icons.close,
        plain: true,
      )));

      final cn = tester.widget<CNButton>(find.byType(CNButton));
      expect(
        cn.config.style,
        CNButtonStyle.plain,
        reason: 'plain must drop the glass capsule so the glyph renders bare',
      );
    });
  });

  testWidgets(
      'kit.ui-library.native-icon-button — default style stays glass on a dark base (regression)',
      (tester) async {
    await withAndroidFallback(() async {
      // Dark theme: no bright opaque base, so the luminance adaptation
      // (pinned in arxa_kit_glass_luminance_test) stays out and the
      // default glass capsule passes through.
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
            body: Center(child: ArxaKitNativeIconButton(icon: Icons.add))),
      ));

      final cn = tester.widget<CNButton>(find.byType(CNButton));
      expect(cn.config.style, CNButtonStyle.glass,
          reason: 'bar actions keep their Liquid Glass circle unless plain '
              'is set or the base is a bright opaque surface');
    });
  });
}
