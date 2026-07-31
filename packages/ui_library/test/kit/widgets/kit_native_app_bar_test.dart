import 'package:flutter/cupertino.dart'
    show CupertinoNavigationBar, CupertinoNavigationBarBackButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart'
    show AppBarM3E, SliverAppBarM3E;
import 'package:appbox_kit_core/platform/kit_platform.dart';
import 'package:ui_library/widgets/kit_native_app_bar.dart';
import 'package:ui_library/ui_library.dart' show KitNativeIconButton, KitGlyphs;

import 'native_test_helpers.dart';

/// Bars-tier gate test — mirrors [kit_native_slider_test]. The load-bearing
/// assertions are the M3E-tier routes: the default ctor must surface an
/// [AppBarM3E] on Android (wantNative) and the `.sliver()` factory must surface a
/// [SliverAppBarM3E] (hosted in a `CustomScrollView`, not `host()`). The default
/// platform lands on a Material [AppBar].
void main() {
  tearDown(KitPlatform.reset);

  testWidgets('default ctor Android wantNative → AppBarM3E', (tester) async {
    KitPlatform.override = const KitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(host(const KitNativeAppBar(title: 'Hi')));

    expect(
      find.byType(AppBarM3E),
      findsOneWidget,
      reason: 'supportsComposeM3E → kit must route to AppBarM3E on Android',
    );
  });

  testWidgets('default ctor builds clean (Material AppBar fallback)',
      (tester) async {
    await tester.pumpWidget(host(const KitNativeAppBar(title: 'Hi')));

    expect(
      find.byType(AppBar),
      findsOneWidget,
      reason: 'default platform (non-Android) → Material AppBar fallback',
    );
    expect(find.text('Hi'), findsOneWidget);
  });

  testWidgets('.sliver() Android wantNative → SliverAppBarM3E', (tester) async {
    KitPlatform.override = const KitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            KitNativeAppBar.sliver(title: 'Sliver'),
          ],
        ),
      ),
    ));

    expect(
      find.byType(SliverAppBarM3E),
      findsOneWidget,
      reason:
          '.sliver() + supportsComposeM3E → kit must route to SliverAppBarM3E',
    );
  });

  testWidgets(
      '.sliver() builds clean on default platform (Material SliverAppBar)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            KitNativeAppBar.sliver(title: 'Sliver'),
          ],
        ),
      ),
    ));

    expect(
      find.byType(SliverAppBar),
      findsOneWidget,
      reason: 'default platform → Material SliverAppBar fallback',
    );
  });

  // ── Chrome guards (Material AppBar tier) ──────────────────────────────────
  // Mirror kit_native_sliver_app_bar_test's inset/gap/center assertions so the
  // fixed + sliver kit bars can't drift. This tier is where the guards live
  // (CN/M3E self-inset + space); the default platform lands here.

  testWidgets('Material tier insets trailing actions by 16 (not hugging)',
      (tester) async {
    const trailing = Key('trailing');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: KitNativeAppBar(
          title: 'T',
          actions: const [SizedBox(key: trailing, width: 24, height: 24)],
        ),
      ),
    ));

    final bar = tester.getRect(find.byType(AppBar));
    final action = tester.getRect(find.byKey(trailing));
    expect(bar.right - action.right, moreOrLessEquals(16, epsilon: 0.5),
        reason: 'kit app bar must inset trailing actions by 16 to match the '
            'CN/M3E tiers (parity with KitNativeSliverAppBar)');
  });

  testWidgets('Material tier spaces adjacent actions by kGap8', (tester) async {
    const left = Key('a-left');
    const right = Key('a-right');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: KitNativeAppBar(
          title: 'T',
          actions: const [
            SizedBox(key: left, width: 24, height: 24),
            SizedBox(key: right, width: 24, height: 24),
          ],
        ),
      ),
    ));

    final l = tester.getRect(find.byKey(left));
    final r = tester.getRect(find.byKey(right));
    expect(r.left - l.right, moreOrLessEquals(8, epsilon: 0.5), // kGap8
        reason: 'kit app bar must gap adjacent actions by kGap8 (Row spacing), '
            'matching the sliver bar + the fixed CN bar');
  });

  testWidgets('Material tier: leading matches trailing (inset, size, center)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: KitNativeAppBar(
          title: 'T',
          leading: const KitNativeIconButton(glyph: KitGlyphs.back),
          actions: const [KitNativeIconButton(glyph: KitGlyphs.more)],
        ),
      ),
    ));

    final bar = tester.getRect(find.byType(AppBar));
    final btns = find.byType(KitNativeIconButton);
    final lead = tester.getRect(btns.first);
    final trail = tester.getRect(btns.last);
    expect(lead.left - bar.left, moreOrLessEquals(16, epsilon: 0.5),
        reason: 'leading must be inset 16 (symmetric with the trailing)');
    expect(bar.right - trail.right, moreOrLessEquals(16, epsilon: 0.5),
        reason: 'trailing stays inset 16');
    expect(lead.height, moreOrLessEquals(trail.height, epsilon: 0.5),
        reason: 'leading + trailing bar buttons must be the same height');
    expect(lead.center.dy, moreOrLessEquals(trail.center.dy, epsilon: 0.5),
        reason: 'leading + trailing must sit on the same vertical center');
  });

  // ── iOS CN tier: bottom breathing room ────────────────────────────────────
  // CupertinoNavigationBar's persistent height is a fixed 44 (== the kit icon
  // button's 44pt tap target), so a bar button sits flush on the content seam.
  // The CN tier reserves a keyed kGap8 gap below the bar so its buttons get the
  // same bottom slack the Material tier gets from centering in kToolbarHeight.
  // A plain SizedBox stands in for the action — a real KitNativeIconButton on
  // iOS builds a native CNButton UiKitView that can't render in a headless test.
  testWidgets('iOS CN tier reserves a kGap8 bottom gap (buttons not flush)',
      (tester) async {
    KitPlatform.override = const KitPlatformOverride(isIOS: true);
    await tester.pumpWidget(host(const KitNativeAppBar(
      title: 'T',
      actions: [SizedBox(width: 24, height: 24)],
    )));

    expect(find.byType(CupertinoNavigationBar), findsOneWidget,
        reason: 'isIOS + wantNative → CupertinoNavigationBar tier');
    final gap = find.byKey(const Key('kitNativeAppBarBottomGap'));
    expect(gap, findsOneWidget,
        reason: 'CN tier must reserve a bottom gap so its 44pt buttons are not '
            'flush on the content seam (parity with the Material tier slack)');
    expect(tester.getSize(gap).height, moreOrLessEquals(8, epsilon: 0.5),
        reason: 'bottom gap == kGap8');
  });

  // ── iOS CN tier: implied leading parity ───────────────────────────────────
  // The stock implied leading on the CN tier is a CupertinoNavigationBarBackButton
  // — visibly different chrome from the KitNativeIconButtons in the trailing
  // slot. The kit implies its OWN back button (a KitNativeIconButton with
  // KitGlyphs.back) so leading + actions match; pop behavior + the localized
  // 'Back' a11y label are preserved. Real KitNativeIconButtons need
  // withAndroidFallback on this host (CN UiKitView can't render headless).

  /// Pumps a two-route app and pushes [page] so the bar's route canPop (the
  /// implied-leading precondition).
  Future<void> pushPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => page)),
          child: const Text('push'),
        ),
      ),
    ));
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
  }

  testWidgets('iOS tier: implied leading is a KitNativeIconButton',
      (tester) async {
    KitPlatform.override = const KitPlatformOverride(isIOS: true);
    await withAndroidFallback(() async {
      await pushPage(
          tester, const Scaffold(appBar: KitNativeAppBar(title: 'Detail')));

      expect(find.byType(CupertinoNavigationBar), findsOneWidget,
          reason: 'isIOS + wantNative → CupertinoNavigationBar tier');
      expect(
        find.descendant(
          of: find.byType(CupertinoNavigationBar),
          matching: find.byType(KitNativeIconButton),
        ),
        findsOneWidget,
        reason: 'implied leading must be the same KitNativeIconButton the '
            'action slots use',
      );
      expect(find.byType(CupertinoNavigationBarBackButton), findsNothing,
          reason: 'the stock Cupertino back button must NOT render');
      final semanticsHandle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Back'), findsOneWidget,
          reason: 'the stock backButtonLabel a11y label is preserved');
      semanticsHandle.dispose();
    });
  });

  testWidgets('iOS tier: tapping the implied leading pops the route',
      (tester) async {
    KitPlatform.override = const KitPlatformOverride(isIOS: true);
    await withAndroidFallback(() async {
      await pushPage(
          tester, const Scaffold(appBar: KitNativeAppBar(title: 'Detail')));
      expect(find.text('Detail'), findsOneWidget);

      await tester.tap(find.byType(KitNativeIconButton));
      await tester.pumpAndSettle();

      expect(find.text('push'), findsOneWidget,
          reason: 'maybePop semantics — tapping the kit back button returns '
              'to the first route');
      expect(find.text('Detail'), findsNothing);
    });
  });

  testWidgets('iOS tier: action buttons still render (no regression)',
      (tester) async {
    KitPlatform.override = const KitPlatformOverride(isIOS: true);
    const a = Key('action-a');
    const b = Key('action-b');
    await withAndroidFallback(() async {
      await pushPage(
        tester,
        Scaffold(
          appBar: KitNativeAppBar(
            title: 'Detail',
            actions: [
              KitNativeIconButton(
                  key: a, glyph: KitGlyphs.more, onPressed: () {}),
              KitNativeIconButton(
                  key: b, glyph: KitGlyphs.back, onPressed: () {}),
            ],
          ),
        ),
      );

      final bar = find.byType(CupertinoNavigationBar);
      expect(find.descendant(of: bar, matching: find.byKey(a)), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.byKey(b)), findsOneWidget,
          reason: 'trailing action buttons render unchanged');
      expect(find.byType(KitNativeIconButton), findsNWidgets(3),
          reason: 'implied leading + the two actions — nothing lost');
    });
  });
}
