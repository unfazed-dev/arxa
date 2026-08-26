import 'package:cupertino_native_better/cupertino_native_better.dart'
    show LiquidGlassContainer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart' show IconButtonM3E;
import 'package:arxa_kit_core/common/arxa_kit_glyphs.dart';
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:text_field_m3e/text_field_m3e.dart' show TextFieldM3E;
import 'package:arxa_kit_ui_library/widgets/arxa_kit_frosted_surface.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_native_icon_button.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_native_input_bar.dart';

import 'arxa_kit_native_test_helpers.dart';

/// Widget tests for [ArxaKitNativeInputBar]. Kit fakes only — never a platform
/// channel: the bar's `wantNative: false` path forces the field to a Material
/// [TextField], and `ArxaKitPlatformOverride(isAndroid: true)` routes the action
/// buttons to [IconButtonM3E] (a pure-Dart widget), so no UiKitView is ever
/// constructed. The native-tier route is asserted separately via
/// [TextFieldM3E] (also pure Dart — the vendored forks carry no bridge).
void main() {
  tearDown(ArxaKitPlatform.reset);

  const addAction = ArxaKitNativeIconButton(glyph: ArxaKitGlyphs.add);
  ArxaKitNativeIconButton micAction(VoidCallback? onPressed) =>
      ArxaKitNativeIconButton(
          glyph: ArxaKitGlyphs.mic, onPressed: onPressed);

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

  testWidgets(
      'kit.ui-library.native-input-bar — Android wantNative routes field + actions to the M3E tier',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await pumpBar(
        tester,
        ArxaKitNativeInputBar(
          hintText: 'Message',
          leading: const [addAction],
          trailing: [micAction(() {})],
        ));

    expect(find.byType(TextFieldM3E), findsOneWidget,
        reason: 'wantNative on Android → the field takes its M3E tier');
    expect(find.byType(IconButtonM3E), findsNWidgets(2),
        reason: 'leading + trailing slots render as M3E icon buttons');
  });

  // The `above` slot docks a row (a composer's pending attachments) INSIDE
  // the bar's anchored opaque backing — the same pinned-chrome layer as the
  // bar. A Flutter-drawn row floating OUTSIDE that layer suffers the
  // view-slicer artifact over platform-view scrollables (luminance wash
  // while scrolling); inside the anchor the fill stays hoisted.
  testWidgets(
      'kit.ui-library.native-input-bar — above slot docks inside the anchored opaque backing',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await pumpBar(
        tester,
        ArxaKitNativeInputBar(
          hintText: 'Message',
          wantNative: false,
          above: const Text('pending-chip'),
          leading: const [addAction],
          trailing: [micAction(() {})],
        ));

    expect(
      find.ancestor(
        of: find.text('pending-chip'),
        matching: find.byType(ArxaKitFrostedSurface),
      ),
      findsOneWidget,
      reason: 'the above row renders inside the bar\'s opaque backing — '
          'the anchored pinned-chrome layer, not floating over the scroll',
    );
  });

  testWidgets(
      'kit.ui-library.native-input-bar — renders field + leading/trailing actions (fallback tiers)',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await pumpBar(
        tester,
        ArxaKitNativeInputBar(
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

  testWidgets('kit.ui-library.native-input-bar — action tap callbacks fire',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    var lead = 0, trail = 0;
    await pumpBar(
        tester,
        ArxaKitNativeInputBar(
          wantNative: false,
          leading: [
            ArxaKitNativeIconButton(
                glyph: ArxaKitGlyphs.add, onPressed: () => lead++),
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

  testWidgets(
      'kit.ui-library.native-input-bar — hint text passes through to the field',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await pumpBar(
        tester,
        const ArxaKitNativeInputBar(
            hintText: 'Ask anything', wantNative: false));

    expect(find.text('Ask anything'), findsOneWidget,
        reason: 'hintText must reach the field as its hint/placeholder');
  });

  testWidgets(
      'kit.ui-library.native-input-bar — onChanged is wired through the field',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    String? fired;
    await pumpBar(
        tester,
        ArxaKitNativeInputBar(
            wantNative: false, onChanged: (v) => fired = v));

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();

    expect(fired, 'hello',
        reason: 'typing in the bar field must fire onChanged');
  });

  testWidgets(
      'kit.ui-library.native-input-bar — keyboard viewInsets lift the bar (keyboard riding)',
      (tester) async {
    addTearDown(tester.view.reset);
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    // resizeToAvoidBottomInset: false so the Scaffold leaves viewInsets in the
    // MediaQuery for the bar to consume itself (the documented host pattern).
    const bar = ArxaKitNativeInputBar(hintText: 'Message', wantNative: false);

    await pumpBar(tester, bar, resizeToAvoidBottomInset: false);
    final closed = tester.getSize(find.byType(ArxaKitNativeInputBar)).height;

    // View insets are PHYSICAL pixels; the test view runs at DPR 3.0, so a
    // 900px keyboard = 300 logical.
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await pumpBar(tester, bar, resizeToAvoidBottomInset: false);
    final open = tester.getSize(find.byType(ArxaKitNativeInputBar)).height;

    expect(open - closed, 300,
        reason: 'the bar must pad by the keyboard inset so it rides the '
            'keyboard in a bottomSheet/Stack/bottomNavigationBar slot');
  });

  testWidgets(
      'kit.ui-library.native-input-bar — bottom SafeArea pads for the home indicator',
      (tester) async {
    addTearDown(tester.view.reset);
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    const bar = ArxaKitNativeInputBar(hintText: 'Message', wantNative: false);

    await pumpBar(tester, bar, resizeToAvoidBottomInset: false);
    final bare = tester.getSize(find.byType(ArxaKitNativeInputBar)).height;

    tester.view.padding =
        const FakeViewPadding(bottom: 72); // 24 logical @ DPR 3
    await pumpBar(tester, bar, resizeToAvoidBottomInset: false);
    final padded = tester.getSize(find.byType(ArxaKitNativeInputBar)).height;

    expect(padded - bare, 24,
        reason: 'with the keyboard closed the bar keeps the bottom safe-area '
            'inset instead of the viewInsets padding');
  });

  testWidgets(
      'kit.ui-library.native-input-bar — actions overriding glyph size trip the one-size assert',
      (tester) async {
    await tester.pumpWidget(host(ArxaKitNativeInputBar(
      wantNative: false,
      trailing: [
        ArxaKitNativeIconButton(glyph: ArxaKitGlyphs.mic, size: 24)
      ],
    )));

    expect(tester.takeException(), isAssertionError,
        reason: 'the bar enforces the one-size bar-glyph contract (18pt '
            'default) — a custom size breaks leading/trailing alignment');
  });

  testWidgets(
      'kit.ui-library.native-input-bar — opaque base rides a plain compositing anchor',
      (tester) async {
    // The anchor (LiquidGlassContainer, CNGlassEffect.plain) is what keeps the
    // opaque base in the slicer overlay above passing platform views — without
    // it the base drops to the background canvas and the bar reads translucent
    // (same mechanism as the floating bar's title pill). Pure Dart here: the
    // vendored container only bridges when a UiKitView materializes.
    await pumpBar(tester,
        const ArxaKitNativeInputBar(hintText: 'Message', wantNative: false));
    expect(
      find.ancestor(
        of: find.byType(SafeArea),
        matching: find.byType(LiquidGlassContainer),
      ),
      findsOneWidget,
      reason: 'opaqueGlass (default) mounts the plain anchor under the base',
    );

    // FULL-OCCLUSION invariant (on-device 2026-08-15; reference fix
    // e75839df). `plain` is NOT pixel-free in practice: any anchor area the
    // opaque base does not cover renders a faint hard-edged luminance
    // rectangle on the Liquid Glass tier. So the anchor wraps EXACTLY the
    // opaque frosted base — the keyboard viewInsets Padding stays OUTSIDE
    // it. Rect equality is the mechanical guard against padding or a
    // transition creeping back inside.
    expect(
      tester.getRect(find.byType(LiquidGlassContainer)),
      tester.getRect(find.byType(ArxaKitFrostedSurface)),
      reason: 'exposed anchor margin renders a hard-edged rect on the glass '
          'tier — keep padding and transitions outside the anchor',
    );

    await pumpBar(
        tester,
        const ArxaKitNativeInputBar(
            hintText: 'Message', wantNative: false, opaqueGlass: false));
    expect(find.byType(LiquidGlassContainer), findsNothing,
        reason: 'transparent backing needs no anchor — nothing to keep opaque');
  });

  testWidgets(
      'kit.ui-library.native-input-bar — tapping a bar action keeps the field '
      'focused (actions join the input tap group)', (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await pumpBar(
        tester,
        ArxaKitNativeInputBar(
          hintText: 'Message',
          wantNative: false,
          leading: const [addAction],
          trailing: [micAction(() {})],
        ));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    final FocusNode node = FocusManager.instance.primaryFocus!;
    expect(node.hasFocus, isTrue, reason: 'precondition: field focused');

    // The regression (2026-08-16, on-device): tapping the bar's own +/mic
    // dropped the keyboard — the actions sat OUTSIDE the field's tap region,
    // so the tap classified as "outside" and ran the dismissal. The bar is one
    // input surface (iOS Messages idiom): an action tap must never dismiss.
    await tester.tap(find.widgetWithIcon(IconButtonM3E, Icons.add));
    await tester.pump();
    expect(node.hasFocus, isTrue,
        reason: 'bar actions are part of the input surface — the keyboard '
            'must survive an action tap');
    await tester.tap(find.widgetWithIcon(IconButtonM3E, Icons.mic));
    await tester.pump();
    expect(node.hasFocus, isTrue,
        reason: 'trailing actions keep the keyboard too (same surface)');

    // The per-input dismissal default itself is unchanged: a tap OUTSIDE the
    // whole bar still dismisses.
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(node.hasFocus, isFalse,
        reason: 'outside taps still dismiss — the fix extends the inside '
            'region, it does not remove dismissal');
  });
}
