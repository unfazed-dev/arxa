import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart' show IconButtonM3E;
import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:text_field_m3e/text_field_m3e.dart' show TextFieldM3E;
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_icon_button.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_input_bar.dart';

import 'appbox_kit_native_test_helpers.dart';

/// Widget tests for [AppBoxKitNativeInputBar]. Kit fakes only — never a platform
/// channel: the bar's `wantNative: false` path forces the field to a Material
/// [TextField], and `AppBoxKitPlatformOverride(isAndroid: true)` routes the action
/// buttons to [IconButtonM3E] (a pure-Dart widget), so no UiKitView is ever
/// constructed. The native-tier route is asserted separately via
/// [TextFieldM3E] (also pure Dart — the vendored forks carry no bridge).
void main() {
  tearDown(AppBoxKitPlatform.reset);

  const addAction = AppBoxKitNativeIconButton(glyph: AppBoxKitGlyphs.add);
  AppBoxKitNativeIconButton micAction(VoidCallback? onPressed) =>
      AppBoxKitNativeIconButton(glyph: AppBoxKitGlyphs.mic, onPressed: onPressed);

  Future<void> pumpBar(
    WidgetTester tester,
    Widget bar, {
    bool resizeToAvoidBottomInset = true,
  }) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          body: Align(alignment: Alignment.bottomCenter, child: bar),
        ),
      ));

  testWidgets('kit.ui-library.native-input-bar — Android wantNative routes field + actions to the M3E tier',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await pumpBar(
        tester,
        AppBoxKitNativeInputBar(
          hintText: 'Message',
          leading: const [addAction],
          trailing: [micAction(() {})],
        ));

    expect(find.byType(TextFieldM3E), findsOneWidget,
        reason: 'wantNative on Android → the field takes its M3E tier');
    expect(find.byType(IconButtonM3E), findsNWidgets(2),
        reason: 'leading + trailing slots render as M3E icon buttons');
  });

  testWidgets('kit.ui-library.native-input-bar — renders field + leading/trailing actions (fallback tiers)',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await pumpBar(
        tester,
        AppBoxKitNativeInputBar(
          hintText: 'Message',
          wantNative: false,
          leading: const [addAction],
          trailing: [micAction(() {})],
        ));

    expect(find.byType(TextField), findsOneWidget,
        reason: 'wantNative: false → Material TextField tier');
    expect(find.byType(IconButtonM3E), findsNWidgets(2));
    expect(find.widgetWithIcon(IconButtonM3E, Icons.add), findsOneWidget,
        reason: 'leading slot renders the add glyph');
    expect(find.widgetWithIcon(IconButtonM3E, Icons.mic), findsOneWidget,
        reason: 'trailing slot renders the mic glyph');
  });

  testWidgets('kit.ui-library.native-input-bar — action tap callbacks fire', (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    var lead = 0, trail = 0;
    await pumpBar(
        tester,
        AppBoxKitNativeInputBar(
          wantNative: false,
          leading: [
            AppBoxKitNativeIconButton(glyph: AppBoxKitGlyphs.add, onPressed: () => lead++),
          ],
          trailing: [micAction(() => trail++)],
        ));

    await tester.tap(find.widgetWithIcon(IconButtonM3E, Icons.add));
    await tester.tap(find.widgetWithIcon(IconButtonM3E, Icons.mic));
    await tester.pump();

    expect(lead, 1,
        reason: 'tapping the leading action must fire its callback');
    expect(trail, 1,
        reason: 'tapping the trailing action must fire its callback');
  });

  testWidgets('kit.ui-library.native-input-bar — hint text passes through to the field', (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    await pumpBar(tester,
        const AppBoxKitNativeInputBar(hintText: 'Ask anything', wantNative: false));

    expect(find.text('Ask anything'), findsOneWidget,
        reason: 'hintText must reach the field as its hint/placeholder');
  });

  testWidgets('kit.ui-library.native-input-bar — onChanged is wired through the field', (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    String? fired;
    await pumpBar(tester,
        AppBoxKitNativeInputBar(wantNative: false, onChanged: (v) => fired = v));

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();

    expect(fired, 'hello',
        reason: 'typing in the bar field must fire onChanged');
  });

  testWidgets('kit.ui-library.native-input-bar — keyboard viewInsets lift the bar (keyboard riding)',
      (tester) async {
    addTearDown(tester.view.reset);
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    // resizeToAvoidBottomInset: false so the Scaffold leaves viewInsets in the
    // MediaQuery for the bar to consume itself (the documented host pattern).
    const bar = AppBoxKitNativeInputBar(hintText: 'Message', wantNative: false);

    await pumpBar(tester, bar, resizeToAvoidBottomInset: false);
    final closed = tester.getSize(find.byType(AppBoxKitNativeInputBar)).height;

    // View insets are PHYSICAL pixels; the test view runs at DPR 3.0, so a
    // 900px keyboard = 300 logical.
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await pumpBar(tester, bar, resizeToAvoidBottomInset: false);
    final open = tester.getSize(find.byType(AppBoxKitNativeInputBar)).height;

    expect(open - closed, 300,
        reason: 'the bar must pad by the keyboard inset so it rides the '
            'keyboard in a bottomSheet/Stack/bottomNavigationBar slot');
  });

  testWidgets('kit.ui-library.native-input-bar — bottom SafeArea pads for the home indicator', (tester) async {
    addTearDown(tester.view.reset);
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(isAndroid: true);
    const bar = AppBoxKitNativeInputBar(hintText: 'Message', wantNative: false);

    await pumpBar(tester, bar, resizeToAvoidBottomInset: false);
    final bare = tester.getSize(find.byType(AppBoxKitNativeInputBar)).height;

    tester.view.padding =
        const FakeViewPadding(bottom: 72); // 24 logical @ DPR 3
    await pumpBar(tester, bar, resizeToAvoidBottomInset: false);
    final padded = tester.getSize(find.byType(AppBoxKitNativeInputBar)).height;

    expect(padded - bare, 24,
        reason: 'with the keyboard closed the bar keeps the bottom safe-area '
            'inset instead of the viewInsets padding');
  });

  testWidgets('kit.ui-library.native-input-bar — actions overriding glyph size trip the one-size assert',
      (tester) async {
    await tester.pumpWidget(host(AppBoxKitNativeInputBar(
      wantNative: false,
      trailing: [AppBoxKitNativeIconButton(glyph: AppBoxKitGlyphs.mic, size: 24)],
    )));

    expect(tester.takeException(), isAssertionError,
        reason: 'the bar enforces the one-size bar-glyph contract (18pt '
            'default) — a custom size breaks leading/trailing alignment');
  });
}
