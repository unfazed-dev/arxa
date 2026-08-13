import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// [AppBoxKitNativeFloatingBar] is the glass tier's top chrome: a floating
/// row over a full-bleed body, whose glass surface is NATIVE so it composites
/// above the platform views scrolling beneath it (allowlist rule 4 — the
/// Flutter-drawn bar could not do this: seam pop or over-bar flash).
void main() {
  Widget harness({Widget? leading, String? title, List<Widget>? actions}) =>
      MaterialApp(
        home: Scaffold(
          body: AppBoxKitNativeFloatingBar(
              leading: leading, title: title, actions: actions),
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

  testWidgets(
      'kit.ui-library.native-floating-bar — leading renders at the row start, '
      'before the title pill, and is absent when null', (tester) async {
    // A pushed route's back affordance (ratified 2026-08-13). Null leading
    // must leave the old layout untouched: the pill starts at the bar's own
    // 16px inset.
    await tester.pumpWidget(harness(title: 'Kit Showcase'));
    final pillLeftWithoutLeading =
        tester.getRect(find.byType(AppBoxKitFrostedSurface).first).left;

    await tester.pumpWidget(harness(
      leading: const SizedBox(key: Key('leading'), width: 44, height: 44),
      title: 'Kit Showcase',
      actions: [const SizedBox(key: Key('action'), width: 44, height: 44)],
    ));
    final leadingRect = tester.getRect(find.byKey(const Key('leading')));
    final pillRect = tester.getRect(find.byType(AppBoxKitFrostedSurface).first);

    expect(leadingRect.left, pillLeftWithoutLeading,
        reason: 'the leading takes the row-start slot the pill used to hold');
    expect(pillRect.left, greaterThanOrEqualTo(leadingRect.right),
        reason: 'the title pill follows the leading, never overlaps it');
    expect(tester.getRect(find.byKey(const Key('action'))).left,
        greaterThan(pillRect.right),
        reason: 'actions still trail everything');
    // Block height is a constant hosts inset by — a leading must not grow it.
    expect(tester.getSize(find.byType(AppBoxKitNativeFloatingBar)).height,
        kAppBoxKitFloatingBarBlockHeight);
  });

  // ---------------------------------------------------------------------
  // AppBoxKitFloatingChrome — scroll-reactive behaviors. All motion must be
  // SLIDE (AnimatedSlide): partial-alpha over the native action buttons is
  // composition rule 1's forbidden shape, and the buttons must stay mounted
  // so restoring never re-materializes glass (clip 13-53-b).
  // ---------------------------------------------------------------------

  Widget chromeHarness(AppBoxKitFloatingBarBehavior behavior,
          {Widget? leading}) =>
      MaterialApp(
        home: Scaffold(
          body: AppBoxKitFloatingChrome(
            behavior: behavior,
            leading: leading,
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

  // ---------------------------------------------------------------------
  // The leading slot's tuck contract (ratified 2026-08-13): minimize moves
  // the title pill and the actions ONLY. Apple keeps the back affordance
  // reachable while the bar minimizes — a back button that slides away on
  // scroll strands the route. `hide` is the one exception, and it comes for
  // free from the whole-bar slide.
  // ---------------------------------------------------------------------

  const leadingProbe = SizedBox(key: Key('leading'), width: 44, height: 44);

  testWidgets(
      'kit.ui-library.floating-chrome — full minimize tucks the pill and the '
      'actions but NEVER the leading', (tester) async {
    await tester.pumpWidget(chromeHarness(
        AppBoxKitFloatingBarBehavior.minimize,
        leading: leadingProbe));
    final resting = tester.getRect(find.byKey(const Key('leading')));

    await scrollAway(tester);
    // The tuck really ran — otherwise leading holding still proves nothing.
    expect(titleSlide(tester).dx, lessThan(0));
    expect(actionsSlide(tester).dx, greaterThan(0));
    // getRect applies ancestor transforms, so an identical rect rules out
    // both a stray slide wrapper and a layout shift.
    expect(tester.getRect(find.byKey(const Key('leading'))), resting,
        reason: 'the back affordance must stay put and stay tappable while '
            'the rest of the bar minimizes');
    expect(
      find.ancestor(
          of: find.byKey(const Key('leading')),
          matching: find.byType(AnimatedSlide)),
      findsNothing,
      reason: 'no slide machinery may wrap the leading at all — a zero '
          'offset today is one refactor away from a tuck',
    );
  });

  testWidgets(
      'kit.ui-library.floating-chrome — minimizeLeading tucks the TITLE PILL, '
      'not the leading slot that shares its name', (tester) async {
    // The naming collision is the trap: AppBoxKitFloatingBarTuck.leading /
    // minimizeLeading name the EDGE the pill leaves by, not this widget.
    await tester.pumpWidget(chromeHarness(
        AppBoxKitFloatingBarBehavior.minimizeLeading,
        leading: leadingProbe));
    final resting = tester.getRect(find.byKey(const Key('leading')));
    await scrollAway(tester);
    expect(titleSlide(tester).dx, lessThan(0));
    expect(tester.getRect(find.byKey(const Key('leading'))), resting);
  });

  testWidgets(
      'kit.ui-library.floating-chrome — hide slides the WHOLE bar away, '
      'leading included', (tester) async {
    await tester.pumpWidget(chromeHarness(AppBoxKitFloatingBarBehavior.hide,
        leading: leadingProbe));
    final resting = tester.getRect(find.byKey(const Key('leading')));
    await scrollAway(tester);
    expect(
      tester.getRect(find.byKey(const Key('leading'))).top,
      lessThan(resting.top),
      reason: 'hide is the one behavior that takes the leading away, and it '
          'falls out of the existing whole-bar AnimatedSlide',
    );
    await scrollBack(tester);
    expect(tester.getRect(find.byKey(const Key('leading'))), resting);
  });

  // ---------------------------------------------------------------------
  // AppBoxKitTopEdgeScrim — the status-bar-zone dissolve. Full-bleed content
  // (native platform views included, per ruling 4) otherwise rides through
  // the status bar fully visible and garbles with the clock/Dynamic Island.
  // The scrim is a Flutter-DRAWN gradient, never an effect: BackdropFilter
  // cannot sample platform-view pixels and an alpha fade over the content
  // saveLayers a platform-view-hosting subtree (composition rule 1).
  //
  // NOTE: these pin the scrim's SHAPE, not that the arrangement is clean on
  // device — a full-width opaque Flutter band over passing platform views is
  // the clip 13-32 shape (see the widget's own doc comment).
  // ---------------------------------------------------------------------

  const statusBar = 47.0;

  /// No Scaffold: it may consume the top padding the scrim and the bar both
  /// measure from, which would make the height pins vacuous.
  Widget scrimHarness(
          {AppBoxKitFloatingBarBehavior behavior =
              AppBoxKitFloatingBarBehavior.pinned}) =>
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: statusBar),
              viewPadding: const EdgeInsets.only(top: statusBar),
            ),
            child: AppBoxKitFloatingChrome(
              behavior: behavior,
              title: 'Kit Showcase',
              actions: [
                const SizedBox(key: Key('action'), width: 44, height: 44)
              ],
              body: ListView(
                children: [
                  for (var i = 0; i < 30; i++)
                    SizedBox(height: 80, key: Key('c$i')),
                ],
              ),
            ),
          ),
        ),
      );

  testWidgets(
      'kit.ui-library.top-edge-scrim — covers the status-bar inset and ends '
      'exactly on the bar\'s bottom edge', (tester) async {
    await tester.pumpWidget(scrimHarness());

    final scrim = tester.getRect(find.byType(AppBoxKitTopEdgeScrim));
    expect(scrim.top, 0, reason: 'the dissolve starts at the physical top');
    expect(scrim.height, greaterThan(statusBar),
        reason: 'an opaque band shorter than the status bar leaves the clock '
            'and Dynamic Island garbling with content — the whole defect');
    expect(scrim.height, statusBar + kAppBoxKitFloatingBarBlockHeight);

    // The alignment that actually matters, and the reason the scrim reads
    // padding.top (the bar's own SafeArea source) rather than a second
    // opinion: the fade must finish where the bar block does, under every
    // inset. Pinning the equality survives whichever source either one picks.
    expect(scrim.height,
        tester.getSize(find.byType(AppBoxKitNativeFloatingBar)).height,
        reason: 'scrim and bar must measure the top inset the same way');
  });

  testWidgets(
      'kit.ui-library.top-edge-scrim — never intercepts taps', (tester) async {
    await tester.pumpWidget(scrimHarness());
    final ignore = tester.widget<IgnorePointer>(
      find
          .descendant(
              of: find.byType(AppBoxKitTopEdgeScrim),
              matching: find.byType(IgnorePointer))
          .first,
    );
    expect(ignore.ignoring, isTrue,
        reason: 'the scrim is decoration over a live scroll view — swallowing '
            'drags in the top band would deaden scrolling under the chrome');
  });

  testWidgets(
      'kit.ui-library.top-edge-scrim — sits UNDER the bar in the chrome Stack '
      'so the bar row stays fully legible above it', (tester) async {
    await tester.pumpWidget(scrimHarness());
    final stack = tester.widget<Stack>(
      find
          .descendant(
              of: find.byType(AppBoxKitFloatingChrome),
              matching: find.byType(Stack))
          .first,
    );
    final scrimIndex = stack.children.indexWhere(
        (child) => child is Positioned && child.child is AppBoxKitTopEdgeScrim);
    expect(scrimIndex, greaterThanOrEqualTo(0),
        reason: 'the scrim must be a sibling in the chrome Stack, not wrapped '
            'around the body (wrapping it would saveLayer the content)');
    expect(scrimIndex, lessThan(stack.children.length - 1),
        reason: 'painted before the bar');
    expect(
      find.descendant(
          of: find.byWidget(stack.children.last),
          matching: find.byType(AppBoxKitNativeFloatingBar)),
      findsOneWidget,
      reason: 'the bar is the LAST child — it paints over the scrim, never '
          'under it',
    );
  });

  testWidgets(
      'kit.ui-library.top-edge-scrim — survives the bar tucking and hiding: '
      'it is what keeps the status bar legible once the bar is gone',
      (tester) async {
    await tester
        .pumpWidget(scrimHarness(behavior: AppBoxKitFloatingBarBehavior.hide));
    final resting = tester.getRect(find.byType(AppBoxKitTopEdgeScrim));

    await scrollAway(tester);
    // The bar really left — otherwise the scrim holding still proves nothing.
    expect(
        tester.getRect(find.byType(AppBoxKitNativeFloatingBar)).top,
        lessThan(0),
        reason: 'hide slid the whole bar off the top');
    expect(tester.getRect(find.byType(AppBoxKitTopEdgeScrim)), resting,
        reason: 'the scrim must NOT ride the whole-bar slide — with the bar '
            'hidden it is the only thing between full-bleed content and the '
            'Dynamic Island');
  });

  testWidgets(
      'kit.ui-library.top-edge-scrim — draws with a gradient fill, adding no '
      'saveLayer and no alpha over the content', (tester) async {
    await tester.pumpWidget(scrimHarness());
    final scrim = find.byType(AppBoxKitTopEdgeScrim);
    // Composition rule 1, mechanically: none of the saveLayer shapes, and no
    // Opacity family, may appear in the scrim subtree. The source-scanning
    // law gate covers the file; this covers the built tree.
    for (final forbidden in <Finder>[
      find.byType(BackdropFilter),
      find.byType(ImageFiltered),
      find.byType(ShaderMask),
      find.byType(Opacity),
      find.byType(AnimatedOpacity),
      find.byType(FadeTransition),
    ]) {
      expect(find.descendant(of: scrim, matching: forbidden), findsNothing,
          reason: 'the scrim must stay a plain gradient fill — effects here '
              'would wrap the platform views passing beneath');
    }

    // The gradient itself: opaque at the top edge, fully clear at the bottom.
    final decoration = tester
        .widget<Container>(
            find.descendant(of: scrim, matching: find.byType(Container)).first)
        .decoration as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors.first.a, 1.0,
        reason: 'opaque where the status bar sits');
    expect(gradient.colors.last.a, 0.0,
        reason: 'fully clear by the bar\'s bottom edge — a residual tint '
            'would haze the whole content top');
    expect(gradient.stops!.first, 0.0);
    expect(gradient.stops![1], statusBar / (statusBar + kAppBoxKitFloatingBarBlockHeight),
        reason: 'the ramp starts only once the status-bar band is cleared');
  });

  testWidgets(
      'kit.ui-library.top-edge-scrim — fadeExtent shortens the ramp for '
      'bar-less hosts so it never washes their resting content',
      (tester) async {
    // Bar-less hosts (the Notes auth panels) inset their content by their own
    // top padding, not the bar block. A ramp longer than that inset lays a
    // partial wash over a heading that never scrolls — the default 52pt ramp
    // would sit ~54% opaque over content starting 24pt down. The ramp must
    // reach fully clear exactly at the host's inset.
    const ramp = 24.0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: statusBar),
            viewPadding: const EdgeInsets.only(top: statusBar),
          ),
          child: const Stack(
            children: [
              Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AppBoxKitTopEdgeScrim(fadeExtent: ramp)),
            ],
          ),
        ),
      ),
    ));

    expect(tester.getSize(find.byType(AppBoxKitTopEdgeScrim)).height,
        statusBar + ramp,
        reason: 'the scrim ends where the host content begins');

    final gradient = (tester
            .widget<Container>(find
                .descendant(
                    of: find.byType(AppBoxKitTopEdgeScrim),
                    matching: find.byType(Container))
                .first)
            .decoration as BoxDecoration)
        .gradient! as LinearGradient;
    // Still opaque across the whole status band — that is the defect being
    // fixed — but clear by the time the resting hero starts.
    expect(gradient.stops![1], statusBar / (statusBar + ramp));
    expect(gradient.colors.last.a, 0.0);
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
