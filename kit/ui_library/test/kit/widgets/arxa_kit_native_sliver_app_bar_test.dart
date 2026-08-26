import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_native_sliver_app_bar.dart';
// Real bar buttons for the leading/trailing symmetry guard — scoped `show` so
// the barrel's own ArxaKitNativeSliverAppBar export doesn't clash with the direct
// import above.
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ArxaKitNativeIconButton, ArxaKitGlyphs;

import 'arxa_kit_native_test_helpers.dart';

void main() {
  testWidgets(
      'kit.ui-library.native-sliver-app-bar — renders as the first sliver of a CustomScrollView and shows its title',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: const [
              ArxaKitNativeSliverAppBar(title: 'Folders'),
              SliverFillRemaining(child: Center(child: Text('body'))),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Folders'), findsOneWidget);
  });

  // Kit default is the stock SliverAppBar sample rhythm: pinned on, floating
  // + snap off. Force
  // the Material tier (wantNative:false) so the underlying SliverAppBar is
  // inspectable, then check the three flags landed.
  testWidgets(
      'kit.ui-library.native-sliver-app-bar — defaults: pinned on, floating + snap off (Material tier)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              const ArxaKitNativeSliverAppBar(title: 'T', wantNative: false),
              const SliverFillRemaining(child: SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
    final bar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
    expect(bar.floating, isFalse);
    expect(bar.pinned, isTrue);
    expect(bar.snap, isFalse);
  });

  // SliverAppBar invariant (Flutter docs): snap may be true only if floating
  // is. The widget bakes the assert so bad call sites fail at construction.
  test(
      'kit.ui-library.native-sliver-app-bar — snap without floating is rejected',
      () {
    expect(
      () => ArxaKitNativeSliverAppBar(floating: false, snap: true),
      throwsA(isA<AssertionError>()),
    );
  });

  // Trailing-action inset (the icon-button "gap"): a bare Material SliverAppBar
  // defaults actionsPadding to EdgeInsets.zero, so a trailing action hugs the
  // screen edge — visibly tighter than the fixed ArxaKitNativeAppBar
  // (CupertinoNavigationBar, whose trailing is inset by _kNavBarEdgePadding =
  // 16). The kit bar sets right:16 so a menu/icon button lands at the same spot
  // in any appbar. This renders the Material tier (wantNative:false = the iOS
  // sliver path) and measures the ACTUAL trailing edge, not just the property —
  // a keyed plain box (no internal padding) so the gap is exactly the inset.
  testWidgets(
      'kit.ui-library.native-sliver-app-bar — Material tier insets trailing actions by 16 (not hugging)',
      (tester) async {
    const trailing = Key('trailing-action');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              const ArxaKitNativeSliverAppBar(
                title: 'T',
                wantNative: false,
                actions: [SizedBox(key: trailing, width: 24, height: 24)],
              ),
              const SliverFillRemaining(child: SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
    // Anchor the bar's right edge on the full-width CustomScrollView — the
    // SliverAppBar's render object is a sliver (not a RenderBox), so getRect
    // can't target it directly.
    final bar = tester.getRect(find.byType(CustomScrollView));
    final action = tester.getRect(find.byKey(trailing));
    // Remove actionsPadding ⇒ gap collapses to ~0 and this fails; that 0-vs-16
    // split is the regression guard for the icon-button placement.
    expect(
      bar.right - action.right,
      moreOrLessEquals(16, epsilon: 0.5),
      reason: 'kit sliver bar must inset its trailing actions by 16 so the '
          'menu/icon button lands where the fixed CN bar puts it',
    );
  });

  // Inter-action spacing: the fixed ArxaKitNativeAppBar (CupertinoNavigationBar)
  // gaps its trailing actions by abxGap8; the kit sliver bar must match so two
  // bar buttons sit the same distance apart in either appbar. Keyed plain boxes
  // (no internal chrome) so the measured gap IS the explicit spacing.
  testWidgets(
      'kit.ui-library.native-sliver-app-bar — Material tier spaces adjacent actions by abxGap8',
      (tester) async {
    const a = Key('action-a');
    const b = Key('action-b');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              ArxaKitNativeSliverAppBar(
                title: 'T',
                wantNative: false,
                actions: [
                  SizedBox(key: a, width: 24, height: 24),
                  SizedBox(key: b, width: 24, height: 24),
                ],
              ),
              SliverFillRemaining(child: SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
    final left = tester.getRect(find.byKey(a));
    final right = tester.getRect(find.byKey(b));
    expect(
      right.left - left.right,
      moreOrLessEquals(8, epsilon: 0.5), // abxGap8 — matches the CN bar

      reason:
          'kit sliver bar must gap adjacent actions by abxGap8 to match the '
          'fixed CN bar (Row spacing: abxGap8)',
    );
  });

  // Leading/trailing symmetry — the "same size + aligned + right padding" ask.
  // Material's leading slot LEFT-aligns AND vertically STRETCHES its child (gap
  // 0, full 56px height), so a bare bar's leading back button hugs the edge and
  // renders TALLER than the trailing actions. The kit bar insets the leading 16
  // (matching the trailing) and centers it at natural size. Uses REAL kit icon
  // buttons so the guard measures what actually renders (height + center), not
  // just padding math.
  testWidgets(
      'kit.ui-library.native-sliver-app-bar — Material tier: leading matches trailing (inset, size, center)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              ArxaKitNativeSliverAppBar(
                title: 'All Notes',
                wantNative: false,
                automaticallyImplyLeading: false,
                leading: ArxaKitNativeIconButton(
                    glyph: ArxaKitGlyphs.back, onPressed: () {}),
                actions: [
                  ArxaKitNativeIconButton(
                      glyph: ArxaKitGlyphs.more, onPressed: () {}),
                ],
              ),
              const SliverFillRemaining(child: SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final bar = tester.getRect(find.byType(CustomScrollView));
    final btns = find.byType(ArxaKitNativeIconButton);
    final lead = tester.getRect(btns.first);
    final trail = tester.getRect(btns.last);
    // Symmetric edge insets: leading gap from left == trailing gap from right.
    expect(lead.left - bar.left, moreOrLessEquals(16, epsilon: 0.5),
        reason: 'leading must be inset 16 (symmetric with the trailing)');
    expect(bar.right - trail.right, moreOrLessEquals(16, epsilon: 0.5),
        reason: 'trailing stays inset 16');
    // Same size: a stretched leading (full bar height) would fail this.
    expect(lead.height, moreOrLessEquals(trail.height, epsilon: 0.5),
        reason: 'leading + trailing bar buttons must be the same height');
    // Aligned: both vertically centered on the same axis.
    expect(lead.center.dy, moreOrLessEquals(trail.center.dy, epsilon: 0.5),
        reason: 'leading + trailing must sit on the same vertical center');
  });

  // When a FlexibleSpaceBar is provided it owns the title (the sample's
  // collapsing-header pattern); the toolbar title is suppressed so the text
  // doesn't render twice.
  testWidgets(
      'kit.ui-library.native-sliver-app-bar — flexibleSpace owns the title (no double render)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              const ArxaKitNativeSliverAppBar(
                title: 'T',
                wantNative: false,
                expandedHeight: 160,
                flexibleSpace: FlexibleSpaceBar(title: Text('T')),
              ),
              const SliverFillRemaining(child: SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
    expect(find.text('T'), findsOneWidget);
  });

  // The background shorthand IS the SliverAppBar sample's full shape —
  // FlexibleSpaceBar(title, background: FlutterLogo()) at expandedHeight 160,
  // with the host's brand mark in the background slot. The kit stays
  // asset-free, so the test passes a keyed box as the stand-in mark.
  testWidgets(
      'kit.ui-library.native-sliver-app-bar — background builds the sample-shaped FlexibleSpaceBar (title + mark, 160)',
      (tester) async {
    const mark = Key('brand-mark');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              const ArxaKitNativeSliverAppBar(
                title: 'T',
                wantNative: false,
                background: SizedBox(key: mark, width: 80, height: 80),
              ),
              const SliverFillRemaining(child: SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(FlexibleSpaceBar),
        matching: find.byKey(mark),
      ),
      findsOneWidget,
      reason: 'the background slot must land inside an auto-built '
          'FlexibleSpaceBar (the sample pattern)',
    );
    expect(
      find.text('T'),
      findsOneWidget,
      reason: 'the auto-built FlexibleSpaceBar owns the title — the toolbar '
          'title must stay suppressed (no double render)',
    );
    final bar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
    expect(
      bar.expandedHeight,
      moreOrLessEquals(160, epsilon: 0.01),
      reason: "a background without an explicit expandedHeight takes the "
          "sample's 160",
    );
  });

  // The 160 is only the sample DEFAULT — a surface needing a taller header
  // keeps its own expandedHeight.
  testWidgets(
      'kit.ui-library.native-sliver-app-bar — explicit expandedHeight beats the background 160 default',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              const ArxaKitNativeSliverAppBar(
                title: 'T',
                wantNative: false,
                expandedHeight: 200,
                background: SizedBox(width: 80, height: 80),
              ),
              const SliverFillRemaining(child: SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
    final bar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
    expect(bar.expandedHeight, moreOrLessEquals(200, epsilon: 0.01));
  });

  // flexibleSpace owns the whole slot — passing both is a caller bug, baked
  // into the constructor like the snap/floating invariant.
  test(
      'kit.ui-library.native-sliver-app-bar — flexibleSpace and background together are rejected',
      () {
    expect(
      () => ArxaKitNativeSliverAppBar(
        flexibleSpace: const FlexibleSpaceBar(),
        background: const SizedBox.shrink(),
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  // ── Implied-leading parity with the fixed bar ─────────────────────────────
  // The sliver bar's iOS path IS the Material tier (no Cupertino sliver bar
  // exists), whose stock implied leading is a Material BackButton — different
  // chrome from the ArxaKitNativeIconButton actions. The kit implies its own back
  // button (same helper as ArxaKitNativeAppBar). withAndroidFallback: a real
  // ArxaKitNativeIconButton builds a CN UiKitView that can't render headless.
  testWidgets(
      'kit.ui-library.native-sliver-app-bar — Material tier: implied leading is a ArxaKitNativeIconButton + pops',
      (tester) async {
    await withAndroidFallback(() async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const Scaffold(
                body: CustomScrollView(
                  slivers: [
                    ArxaKitNativeSliverAppBar(title: 'Detail'),
                    SliverFillRemaining(child: SizedBox.shrink()),
                  ],
                ),
              ),
            )),
            child: const Text('push'),
          ),
        ),
      ));
      await tester.tap(find.text('push'));
      await tester.pumpAndSettle();

      expect(find.byType(ArxaKitNativeIconButton), findsOneWidget,
          reason:
              'implied leading must be the same ArxaKitNativeIconButton the '
              'action slots use (parity with ArxaKitNativeAppBar)');
      expect(find.byType(BackButton), findsNothing,
          reason: 'the stock Material BackButton must NOT render');

      await tester.tap(find.byType(ArxaKitNativeIconButton));
      await tester.pumpAndSettle();
      expect(find.text('push'), findsOneWidget,
          reason: 'maybePop semantics — tapping the kit back button pops');
    });
  });
}
