import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// [AppBoxKitNativeFloatingBar] is the glass tier's top chrome: a floating
/// row over a full-bleed body, whose glass surface is NATIVE so it composites
/// above the platform views scrolling beneath it (allowlist rule 4 — the
/// Flutter-drawn bar could not do this: seam pop or over-bar flash).
void main() {
  Widget harness({String? title, List<Widget>? actions}) => MaterialApp(
        home: Scaffold(
          body: AppBoxKitNativeFloatingBar(title: title, actions: actions),
        ),
      );

  testWidgets(
      'kit.ui-library.native-floating-bar — title rides a native glass '
      'capsule and actions land trailing in the 44pt control row',
      (tester) async {
    await tester.pumpWidget(harness(
      title: 'Kit Showcase',
      actions: [const SizedBox(key: Key('action'), width: 44, height: 44)],
    ));

    // The title pill must be the FLUTTER-DRAWN platform-view-safe frosted
    // surface, NOT native glass: scrolled native glass buttons crossing a
    // native capsule stack glass-on-glass and wash to square ghosts for
    // exactly the capsule's span (clip 13-53). This pin is the regression
    // guard for that ruling — do not "upgrade" the title back to
    // LiquidGlassContainer.
    final pill = tester.widget<AppBoxKitFrostedSurface>(
      find
          .ancestor(
            of: find.text('Kit Showcase'),
            matching: find.byType(AppBoxKitFrostedSurface),
          )
          .first,
    );
    expect(pill.platformViewSafe, isTrue,
        reason: 'a BackdropFilter pill would saveLayer over the platform '
            'views passing beneath (composition rule 1)');

    // Control row is exactly 44 — the same block the boxed bar reserves, so
    // kAppBoxKitFloatingBarBlockHeight stays honest.
    final row = tester.getRect(find.byKey(const Key('action')));
    expect(row.height, 44);

    // Actions trail the title.
    expect(row.left,
        greaterThan(tester.getRect(find.text('Kit Showcase')).right));
  });

  testWidgets(
      'kit.ui-library.native-floating-bar — block height constant matches '
      'the laid-out bar (44 control row + breathing gap)', (tester) async {
    await tester.pumpWidget(harness(title: 'T'));
    // No status bar in the test env, so the bar's total height IS the block.
    expect(
      tester.getSize(find.byType(AppBoxKitNativeFloatingBar)).height,
      kAppBoxKitFloatingBarBlockHeight,
      reason: 'hosts inset full-bleed content by this constant; if the bar '
          'grows, the constant must grow with it',
    );
  });

  testWidgets(
      'kit.ui-library.native-floating-bar — null title and actions render an '
      'empty row without throwing', (tester) async {
    await tester.pumpWidget(harness());
    expect(find.byType(AppBoxKitNativeFloatingBar), findsOneWidget);
    expect(find.byType(AppBoxKitFrostedSurface), findsNothing);
  });

  // ---------------------------------------------------------------------
  // AppBoxKitFloatingChrome — scroll-reactive behaviors. All motion must be
  // SLIDE (AnimatedSlide): partial-alpha over the native action buttons is
  // composition rule 1's forbidden shape, and the buttons must stay mounted
  // so restoring never re-materializes glass (clip 13-53-b).
  // ---------------------------------------------------------------------

  Widget chromeHarness(AppBoxKitFloatingBarBehavior behavior) => MaterialApp(
        home: Scaffold(
          body: AppBoxKitFloatingChrome(
            behavior: behavior,
            title: 'Kit Showcase',
            actions: [const SizedBox(key: Key('action'), width: 44, height: 44)],
            body: ListView(
              children: [
                for (var i = 0; i < 30; i++) SizedBox(height: 80, key: Key('c$i')),
              ],
            ),
          ),
        ),
      );

  Offset actionsSlide(WidgetTester tester) => tester
      .widget<AnimatedSlide>(
        find
            .ancestor(
                of: find.byKey(const Key('action')),
                matching: find.byType(AnimatedSlide))
            .first,
      )
      .offset;

  Future<void> scrollAway(WidgetTester tester) async {
    await tester.fling(find.byType(ListView), const Offset(0, -400), 800);
    await tester.pumpAndSettle();
  }

  Future<void> scrollBack(WidgetTester tester) async {
    await tester.fling(find.byType(ListView), const Offset(0, 200), 800);
    await tester.pumpAndSettle();
  }

  Offset titleSlide(WidgetTester tester) => tester
      .widget<AnimatedSlide>(
        find
            .ancestor(
                of: find.text('Kit Showcase'),
                matching: find.byType(AnimatedSlide))
            .first,
      )
      .offset;

  testWidgets(
      'kit.ui-library.floating-chrome — minimize tucks BOTH ends on '
      'scroll-away, restores on scroll-back, and never unmounts the actions',
      (tester) async {
    await tester
        .pumpWidget(chromeHarness(AppBoxKitFloatingBarBehavior.minimize));
    expect(actionsSlide(tester), Offset.zero);
    expect(titleSlide(tester), Offset.zero);

    await scrollAway(tester);
    expect(actionsSlide(tester).dx, greaterThan(0),
        reason: 'full minimize slides the actions off the trailing edge');
    expect(titleSlide(tester).dx, lessThan(0),
        reason: 'full minimize slides the pill off the leading edge too');
    expect(find.byKey(const Key('action'), skipOffstage: false), findsOneWidget,
        reason: 'tucked actions stay mounted — unmounting would '
            're-materialize glass on restore');

    await scrollBack(tester);
    expect(actionsSlide(tester), Offset.zero);
    expect(titleSlide(tester), Offset.zero);
  });

  testWidgets(
      'kit.ui-library.floating-chrome — minimizeTrailing tucks only the '
      'actions; the title pill stays', (tester) async {
    await tester.pumpWidget(
        chromeHarness(AppBoxKitFloatingBarBehavior.minimizeTrailing));
    await scrollAway(tester);
    expect(actionsSlide(tester).dx, greaterThan(0));
    expect(titleSlide(tester), Offset.zero);
    await scrollBack(tester);
    expect(actionsSlide(tester), Offset.zero);
  });

  testWidgets(
      'kit.ui-library.floating-chrome — minimizeLeading tucks the title pill '
      'instead, and the actions stay put', (tester) async {
    await tester
        .pumpWidget(chromeHarness(AppBoxKitFloatingBarBehavior.minimizeLeading));
    Offset titleSlide() => tester
        .widget<AnimatedSlide>(
          find
              .ancestor(
                  of: find.text('Kit Showcase'),
                  matching: find.byType(AnimatedSlide))
              .first,
        )
        .offset;
    expect(titleSlide(), Offset.zero);
    await scrollAway(tester);
    expect(titleSlide().dx, lessThan(0),
        reason: 'leading tuck slides the pill off the LEFT edge');
    expect(actionsSlide(tester), Offset.zero,
        reason: 'the mirrored variant leaves the actions in place');
    await scrollBack(tester);
    expect(titleSlide(), Offset.zero);
  });

  testWidgets(
      'kit.ui-library.floating-chrome — sub-threshold jitter never toggles '
      '(24px hysteresis on committed travel)', (tester) async {
    await tester
        .pumpWidget(chromeHarness(AppBoxKitFloatingBarBehavior.minimize));
    // Scroll away for real, then jitter back by less than the threshold:
    // the chrome must stay tucked.
    await scrollAway(tester);
    expect(actionsSlide(tester).dx, greaterThan(0));
    await tester.drag(find.byType(ListView), const Offset(0, 10));
    await tester.pumpAndSettle();
    expect(actionsSlide(tester).dx, greaterThan(0),
        reason: '10px of reverse travel is jitter, not intent');
  });

  testWidgets(
      'kit.ui-library.floating-chrome — pinned ignores scrolling entirely',
      (tester) async {
    await tester.pumpWidget(chromeHarness(AppBoxKitFloatingBarBehavior.pinned));
    await scrollAway(tester);
    expect(actionsSlide(tester), Offset.zero);
  });

  testWidgets(
      'kit.ui-library.floating-chrome — hide slides the whole bar up and back',
      (tester) async {
    await tester.pumpWidget(chromeHarness(AppBoxKitFloatingBarBehavior.hide));
    Offset barSlide() => tester
        .widget<AnimatedSlide>(
          find
              .ancestor(
                  of: find.byType(AppBoxKitNativeFloatingBar),
                  matching: find.byType(AnimatedSlide))
              .first,
        )
        .offset;
    expect(barSlide(), Offset.zero);
    await scrollAway(tester);
    expect(barSlide().dy, lessThan(0));
    // Actions must NOT double-slide in hide mode.
    expect(actionsSlide(tester), Offset.zero);
    await scrollBack(tester);
    expect(barSlide(), Offset.zero);
  });

  testWidgets(
      'kit.ui-library.floating-chrome — raises the body MediaQuery top '
      'padding by the bar block so descendants inset themselves',
      (tester) async {
    double? seen;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppBoxKitFloatingChrome(
          title: 'T',
          body: Builder(builder: (context) {
            seen = MediaQuery.paddingOf(context).top;
            return const SizedBox();
          }),
        ),
      ),
    ));
    expect(seen, kAppBoxKitFloatingBarBlockHeight,
        reason: 'test env has no status bar, so the raise IS the block');
  });
}
