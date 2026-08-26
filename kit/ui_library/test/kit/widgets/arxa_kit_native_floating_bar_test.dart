import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNGlassEffect, LiquidGlassContainer;
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

/// [ArxaKitNativeFloatingBar] is the glass tier's top chrome: a floating
/// row over a full-bleed body, whose glass surface is NATIVE so it composites
/// above the platform views scrolling beneath it (allowlist rule 4 — the
/// Flutter-drawn bar could not do this: seam pop or over-bar flash).
void main() {
  Widget harness({Widget? leading, String? title, List<Widget>? actions}) =>
      MaterialApp(
        home: Scaffold(
          body: ArxaKitNativeFloatingBar(
              leading: leading, title: title, actions: actions),
        ),
      );

  testWidgets(
      'kit.ui-library.native-floating-bar — title rides a native glass '
      'capsule and actions land trailing in the 44pt control row',
      (tester) async {
    await tester.pumpWidget(harness(
      title: 'Arxa Showcase',
      actions: [const SizedBox(key: Key('action'), width: 44, height: 44)],
    ));

    // The title pill must be the FLUTTER-DRAWN platform-view-safe frosted
    // surface, NOT native glass: scrolled native glass buttons crossing a
    // native capsule stack glass-on-glass and wash to square ghosts for
    // exactly the capsule's span (clip 13-53). This pin is the regression
    // guard for that ruling — do not "upgrade" the title back to a GLASS
    // LiquidGlassContainer.
    final pill = tester.widget<ArxaKitFrostedSurface>(
      find
          .ancestor(
            of: find.text('Arxa Showcase'),
            matching: find.byType(ArxaKitFrostedSurface),
          )
          .first,
    );
    expect(pill.platformViewSafe, isTrue,
        reason: 'a BackdropFilter pill would saveLayer over the platform '
            'views passing beneath (composition rule 1)');

    // …but the pill MUST ride a PLAIN native anchor: without a stationary
    // platform view beneath it, the engine's view slicer drops the pill's
    // ops to the difference-clipped background canvas whenever the body's
    // platform views scroll away (top rubber-band), erasing the pill on
    // device (clip 21-32 + composited-window probe, 2026-08-13). `plain`
    // renders no glass material, so this does not reopen the 13-53 ban.
    final anchor = tester.widget<LiquidGlassContainer>(
      find
          .ancestor(
            of: find.text('Arxa Showcase'),
            matching: find.byType(LiquidGlassContainer),
          )
          .first,
    );
    expect(anchor.config.effect, CNGlassEffect.plain,
        reason: 'a glass-effect capsule would stack glass-on-glass with '
            'passing controls (clip 13-53); no anchor at all re-opens the '
            'overscroll erasure (view_slicer geometry)');
    expect(anchor.config.tint, isNull,
        reason: 'the anchor is a compositing fixture, not a visible surface '
            '— the frosted pill above it owns every visible pixel');

    // FULL-OCCLUSION invariant (on-device 2026-08-15; reference fix
    // e75839df). `plain` is NOT pixel-free in practice: any anchor area the
    // opaque pill does not cover renders a faint hard-edged luminance
    // rectangle on the Liquid Glass tier. So the anchor must wrap EXACTLY
    // the decorated pill — the tuck AnimatedSlide and every gap stay
    // OUTSIDE it. Rect equality is the mechanical guard: interpose a
    // Padding, an Align or a slack SizedBox and this fails.
    expect(
      tester.getRect(find
          .ancestor(
            of: find.text('Arxa Showcase'),
            matching: find.byType(LiquidGlassContainer),
          )
          .first),
      tester.getRect(find
          .ancestor(
            of: find.text('Arxa Showcase'),
            matching: find.byType(ArxaKitFrostedSurface),
          )
          .first),
      reason: 'exposed anchor margin renders a hard-edged rect on the glass '
          'tier — keep transitions and padding outside the anchor',
    );

    // Control row is exactly 44 — the same block the boxed bar reserves, so
    // kArxaKitFloatingBarBlockHeight stays honest.
    final row = tester.getRect(find.byKey(const Key('action')));
    expect(row.height, 44);

    // Actions trail the title.
    expect(row.left,
        greaterThan(tester.getRect(find.text('Arxa Showcase')).right));
  });

  testWidgets(
      'kit.ui-library.native-floating-bar — an over-long title truncates '
      'inside the pill instead of overflowing the control row', (tester) async {
    // The 358pt configuration the 2026-08-17 'Kit Showcase' →
    // 'Arxa Showcase' rename overflowed by 31px on the glass tier: the
    // title pill must yield the way native chrome does — truncate the title —
    // never push the trailing actions off the bar.
    tester.view.physicalSize = const Size(1074, 2400); // 358×800 logical
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(
      title: 'Arxa Showcase',
      actions: const [
        SizedBox(key: Key('a1'), width: 44, height: 44),
        SizedBox(key: Key('a2'), width: 44, height: 44),
      ],
    ));

    expect(tester.takeException(), isNull,
        reason: 'the control row must absorb an over-long title, not overflow');
    expect(tester.getRect(find.text('Arxa Showcase')).right,
        lessThanOrEqualTo(tester.getRect(find.byKey(const Key('a1'))).left),
        reason: 'the truncated title never runs under the trailing actions');
  });

  testWidgets(
      'kit.ui-library.native-floating-bar — block height constant matches '
      'the laid-out bar (44 control row + breathing gap)', (tester) async {
    await tester.pumpWidget(harness(title: 'T'));
    // No status bar in the test env, so the bar's total height IS the block.
    expect(
      tester.getSize(find.byType(ArxaKitNativeFloatingBar)).height,
      kArxaKitFloatingBarBlockHeight,
      reason: 'hosts inset full-bleed content by this constant; if the bar '
          'grows, the constant must grow with it',
    );
  });

  testWidgets(
      'kit.ui-library.native-floating-bar — null title and actions render an '
      'empty row without throwing', (tester) async {
    await tester.pumpWidget(harness());
    expect(find.byType(ArxaKitNativeFloatingBar), findsOneWidget);
    expect(find.byType(ArxaKitFrostedSurface), findsNothing);
  });

  testWidgets(
      'kit.ui-library.native-floating-bar — leading renders at the row start, '
      'before the title pill, and is absent when null', (tester) async {
    // A pushed route's back affordance (ratified 2026-08-13). Null leading
    // must leave the old layout untouched: the pill starts at the bar's own
    // 16px inset.
    await tester.pumpWidget(harness(title: 'Arxa Showcase'));
    final pillLeftWithoutLeading =
        tester.getRect(find.byType(ArxaKitFrostedSurface).first).left;

    await tester.pumpWidget(harness(
      leading: const SizedBox(key: Key('leading'), width: 44, height: 44),
      title: 'Arxa Showcase',
      actions: [const SizedBox(key: Key('action'), width: 44, height: 44)],
    ));
    final leadingRect = tester.getRect(find.byKey(const Key('leading')));
    final pillRect = tester.getRect(find.byType(ArxaKitFrostedSurface).first);

    expect(leadingRect.left, pillLeftWithoutLeading,
        reason: 'the leading takes the row-start slot the pill used to hold');
    expect(pillRect.left, greaterThanOrEqualTo(leadingRect.right),
        reason: 'the title pill follows the leading, never overlaps it');
    expect(tester.getRect(find.byKey(const Key('action'))).left,
        greaterThan(pillRect.right),
        reason: 'actions still trail everything');
    // Block height is a constant hosts inset by — a leading must not grow it.
    expect(tester.getSize(find.byType(ArxaKitNativeFloatingBar)).height,
        kArxaKitFloatingBarBlockHeight);
  });

  // ---------------------------------------------------------------------
  // ArxaKitFloatingChrome — scroll-reactive behaviors. All motion must be
  // SLIDE (AnimatedSlide): partial-alpha over the native action buttons is
  // composition rule 1's forbidden shape, and the buttons must stay mounted
  // so restoring never re-materializes glass (clip 13-53-b).
  // ---------------------------------------------------------------------

  Widget chromeHarness(ArxaKitFloatingBarBehavior behavior,
          {Widget? leading}) =>
      MaterialApp(
        home: Scaffold(
          body: ArxaKitFloatingChrome(
            behavior: behavior,
            leading: leading,
            title: 'Arxa Showcase',
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
                of: find.text('Arxa Showcase'),
                matching: find.byType(AnimatedSlide))
            .first,
      )
      .offset;

  testWidgets(
      'kit.ui-library.floating-chrome — minimize tucks BOTH ends on '
      'scroll-away, restores on scroll-back, and never unmounts the actions',
      (tester) async {
    await tester
        .pumpWidget(chromeHarness(ArxaKitFloatingBarBehavior.minimize));
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
        chromeHarness(ArxaKitFloatingBarBehavior.minimizeTrailing));
    await scrollAway(tester);
    expect(actionsSlide(tester).dx, greaterThan(0));
    expect(titleSlide(tester), Offset.zero);
    await scrollBack(tester);
    expect(actionsSlide(tester), Offset.zero);
  });

  testWidgets(
      'kit.ui-library.floating-chrome — minimizeLeading tucks the title pill '
      'instead, and the actions stay put', (tester) async {
    await tester.pumpWidget(
        chromeHarness(ArxaKitFloatingBarBehavior.minimizeLeading));
    Offset titleSlide() => tester
        .widget<AnimatedSlide>(
          find
              .ancestor(
                  of: find.text('Arxa Showcase'),
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
        .pumpWidget(chromeHarness(ArxaKitFloatingBarBehavior.minimize));
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
    await tester.pumpWidget(chromeHarness(ArxaKitFloatingBarBehavior.pinned));
    await scrollAway(tester);
    expect(actionsSlide(tester), Offset.zero);
  });

  testWidgets(
      'kit.ui-library.floating-chrome — hide slides the whole bar up and back',
      (tester) async {
    await tester.pumpWidget(chromeHarness(ArxaKitFloatingBarBehavior.hide));
    Offset barSlide() => tester
        .widget<AnimatedSlide>(
          find
              .ancestor(
                  of: find.byType(ArxaKitNativeFloatingBar),
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
  // The leading slot's tuck contract (device ruling 2026-08-13, clip 22-34,
  // superseding the same-day never-tucks ratification): the leading rides
  // the LEADING edge with the title pill — the pill sliding away alone
  // while the back button stayed read as a half-minimized bar. Scroll-back
  // or the top restores both, so the route is never stranded. It slides,
  // never fades, and stays mounted (clip 13-53-b), like both other ends.
  // ---------------------------------------------------------------------

  const leadingProbe = SizedBox(key: Key('leading'), width: 44, height: 44);

  Offset leadingSlide(WidgetTester tester) => tester
      .widget<AnimatedSlide>(
        find
            .ancestor(
                of: find.byKey(const Key('leading')),
                matching: find.byType(AnimatedSlide))
            .first,
      )
      .offset;

  testWidgets(
      'kit.ui-library.floating-chrome — full minimize tucks the leading off '
      'the LEFT edge with the pill, and never unmounts it', (tester) async {
    await tester.pumpWidget(chromeHarness(ArxaKitFloatingBarBehavior.minimize,
        leading: leadingProbe));
    expect(leadingSlide(tester), Offset.zero);

    await scrollAway(tester);
    expect(titleSlide(tester).dx, lessThan(0));
    expect(actionsSlide(tester).dx, greaterThan(0));
    expect(leadingSlide(tester).dx, lessThan(0),
        reason: 'the back affordance tucks with the leading edge — a pill '
            'that leaves without it reads as a half-minimized bar');
    expect(
        find.byKey(const Key('leading'), skipOffstage: false), findsOneWidget,
        reason: 'tucked leading stays mounted — unmounting would '
            're-materialize glass on restore');

    await scrollBack(tester);
    expect(leadingSlide(tester), Offset.zero);
  });

  testWidgets(
      'kit.ui-library.floating-chrome — minimizeLeading tucks the leading '
      'with the title pill; minimizeTrailing leaves it put', (tester) async {
    await tester.pumpWidget(chromeHarness(
        ArxaKitFloatingBarBehavior.minimizeLeading,
        leading: leadingProbe));
    await scrollAway(tester);
    expect(titleSlide(tester).dx, lessThan(0));
    expect(leadingSlide(tester).dx, lessThan(0));

    await tester.pumpWidget(chromeHarness(
        ArxaKitFloatingBarBehavior.minimizeTrailing,
        leading: leadingProbe));
    await scrollBack(tester);
    await scrollAway(tester);
    expect(actionsSlide(tester).dx, greaterThan(0));
    expect(leadingSlide(tester), Offset.zero,
        reason: 'trailing-only minimize moves the actions, not the leading');
  });

  testWidgets(
      'kit.ui-library.floating-chrome — hide slides the WHOLE bar away, '
      'leading included', (tester) async {
    await tester.pumpWidget(chromeHarness(ArxaKitFloatingBarBehavior.hide,
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
  // Route-transform containment (device clip: tucked chrome flashing mid
  // back-swipe). The minimize tuck parks the leading + pill off the LEFT
  // screen edge with a transform — it never UNPAINTS them. A Cupertino
  // back-swipe translates the whole outgoing route right by up to a full
  // screen width, and that transform is an ancestor of the bar, so the
  // parked widgets ride it straight back into the visible frame. Untucked
  // chrome rides the same transform at its normal position, which is why
  // the defect only ever showed when tucked. The bar's answer is a hard
  // ClipRect at its own bounds: the box rides the same route transform, so
  // paint is culled at the route edge no matter where the route is.
  // ---------------------------------------------------------------------

  testWidgets(
      'kit.ui-library.floating-chrome — a back-swipe cannot drag tucked '
      'chrome back on screen: the bar hard-clips its ends to its own bounds',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    Widget swipeHarness() => MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('root-page')),
        );

    await tester.pumpWidget(swipeHarness());
    navigatorKey.currentState!.push(
      CupertinoPageRoute<void>(
        builder: (_) => Scaffold(
          body: ArxaKitFloatingChrome(
            behavior: ArxaKitFloatingBarBehavior.minimize,
            leading: const SizedBox(key: Key('leading'), width: 44, height: 44),
            title: 'Arxa Showcase',
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
    await tester.pumpAndSettle();

    // Tuck for real: the pill and leading slide off the left edge and STAY
    // painted (transform, never unmount — clip 13-53-b).
    await tester.fling(find.byType(ListView), const Offset(0, -400), 800);
    await tester.pumpAndSettle();
    expect(titleSlide(tester).dx, lessThan(0));
    expect(leadingSlide(tester).dx, lessThan(0));

    final clipFinder = find.ancestor(
      of: find.text('Arxa Showcase'),
      matching: find.byType(ClipRect),
    );
    final viewport = Offset.zero & tester.binding.renderViews.first.size;

    // Edge-drag a back-swipe, sampling every frame of the drag: the window
    // the device clip shows the tucked pills flashing in.
    final gesture = await tester.startGesture(const Offset(5.0, 200.0));
    await gesture.moveBy(const Offset(30.0, 0.0));
    await tester.pump();

    var sawCarriedOnScreen = false;
    Future<void> sample() async {
      final pillRect = tester.getRect(find.text('Arxa Showcase'));
      if (pillRect.overlaps(viewport)) sawCarriedOnScreen = true;
      final leadingRect = tester.getRect(find.byKey(const Key('leading')));
      for (final rect in [pillRect, leadingRect]) {
        if (!rect.overlaps(viewport)) continue;
        // The clip exists, is HARD (no saveLayer), sits at the bar's own
        // bounds, and culls every pixel the swipe carried back on screen.
        expect(clipFinder, findsOneWidget,
            reason: 'the swipe carried a tucked widget back into the viewport '
                "and nothing bounds the bar's paint — the reported flash");
        expect(tester.widget<ClipRect>(clipFinder).clipBehavior, Clip.hardEdge,
            reason: 'hard paint culling, no saveLayer — an anti-aliased or '
                'effect-based edge is composition rule 1 territory');
        final clipRect = tester.getRect(clipFinder);
        expect(
            clipRect, tester.getRect(find.byType(ArxaKitNativeFloatingBar)),
            reason: "containment lives at the bar's own box, which rides the "
                'same route transform as the tucked ends');
        expect(clipRect.intersect(rect).isEmpty, isTrue,
            reason: 'a tucked widget the swipe dragged back on screen must be '
                "paint-culled at the bar's bounds, not rendered");
      }
    }

    await sample();
    // Past the halfway line so the release COMMITS the pop (8×60+30 = 510 of
    // the 800pt surface) — a cancel keeps the route and the final pop check
    // below would go vacuous.
    for (var step = 0; step < 8; step++) {
      await gesture.moveBy(const Offset(60.0, 0.0));
      await tester.pump(const Duration(milliseconds: 16));
      await sample();
    }
    expect(sawCarriedOnScreen, isTrue,
        reason: 'anti-vacuity: the drag must genuinely carry the tucked pill '
            'back into the viewport, or the clip assertions above prove nothing');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('root-page'), findsOneWidget,
        reason: 'the swipe must actually have popped — otherwise the drag '
            'samples above asserted nothing about a real back-swipe');
  });

  testWidgets(
      'kit.ui-library.floating-chrome — the containment clip is '
      'horizontal-only so the pill shadow feathers past the slot',
      (tester) async {
    // The first containment clip bounded the bar's whole slot rect — and
    // hard-cut the title pill's BoxShadow (blurRadius 16, offset (0, 4):
    // ~20px of feather below the pill against the slot's 8px bottom slack,
    // visible as a sliced shadow on device. The clip's JOB is horizontal:
    // the tucks slide horizontally, and the back-swipe carries parked ends
    // back in horizontally. Vertically the slot is already bounded by the
    // physical screen edge, exactly as before containment existed. So the
    // clipper must clip x to the slot and leave y open.
    await tester
        .pumpWidget(chromeHarness(ArxaKitFloatingBarBehavior.minimize));
    final clipFinder = find.ancestor(
      of: find.text('Arxa Showcase'),
      matching: find.byType(ClipRect),
    );
    expect(clipFinder, findsOneWidget);
    final size = tester.getSize(clipFinder);
    final clip = tester.widget<ClipRect>(clipFinder).clipper?.getClip(size);
    expect(clip, isNotNull,
        reason: 'a null clipper clips to the widget rect — the shadow-slicing '
            'slot bounds this test guards against');
    expect(clip!.left, 0,
        reason:
            'leading-edge containment is the back-swipe fix — do not loosen');
    expect(clip.right, size.width,
        reason:
            'trailing-edge containment is the forward-push fix — do not loosen');
    expect(clip.top, lessThan(0),
        reason: 'the pill shadow feathers upward past the slot top too');
    expect(clip.bottom, greaterThan(size.height + 16),
        reason: 'the pill\'s BoxShadow (blur 16, offset (0,4)) needs ~20px '
            'below the pill; the slot reserves only 8 — a slot-bottom clip '
            'hard-cuts the feather mid-fade (the luminance/shadow regression)');
  });

  // ---------------------------------------------------------------------
  // ArxaKitTopEdgeScrim — the status-bar-zone dissolve. Full-bleed content
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
          {ArxaKitFloatingBarBehavior behavior =
              ArxaKitFloatingBarBehavior.pinned}) =>
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: statusBar),
              viewPadding: const EdgeInsets.only(top: statusBar),
            ),
            child: ArxaKitFloatingChrome(
              behavior: behavior,
              title: 'Arxa Showcase',
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

    final scrim = tester.getRect(find.byType(ArxaKitTopEdgeScrim));
    expect(scrim.top, 0, reason: 'the dissolve starts at the physical top');
    expect(scrim.height, greaterThan(statusBar),
        reason: 'an opaque band shorter than the status bar leaves the clock '
            'and Dynamic Island garbling with content — the whole defect');
    expect(scrim.height, statusBar + kArxaKitFloatingBarBlockHeight);

    // The alignment that actually matters, and the reason the scrim reads
    // padding.top (the bar's own SafeArea source) rather than a second
    // opinion: the fade must finish where the bar block does, under every
    // inset. Pinning the equality survives whichever source either one picks.
    expect(scrim.height,
        tester.getSize(find.byType(ArxaKitNativeFloatingBar)).height,
        reason: 'scrim and bar must measure the top inset the same way');
  });

  testWidgets('kit.ui-library.top-edge-scrim — never intercepts taps',
      (tester) async {
    await tester.pumpWidget(scrimHarness());
    final ignore = tester.widget<IgnorePointer>(
      find
          .descendant(
              of: find.byType(ArxaKitTopEdgeScrim),
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
              of: find.byType(ArxaKitFloatingChrome),
              matching: find.byType(Stack))
          .first,
    );
    final scrimIndex = stack.children.indexWhere(
        (child) => child is Positioned && child.child is ArxaKitTopEdgeScrim);
    expect(scrimIndex, greaterThanOrEqualTo(0),
        reason: 'the scrim must be a sibling in the chrome Stack, not wrapped '
            'around the body (wrapping it would saveLayer the content)');
    expect(scrimIndex, lessThan(stack.children.length - 1),
        reason: 'painted before the bar');
    expect(
      find.descendant(
          of: find.byWidget(stack.children.last),
          matching: find.byType(ArxaKitNativeFloatingBar)),
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
        .pumpWidget(scrimHarness(behavior: ArxaKitFloatingBarBehavior.hide));
    final resting = tester.getRect(find.byType(ArxaKitTopEdgeScrim));

    await scrollAway(tester);
    // The bar really left — otherwise the scrim holding still proves nothing.
    expect(tester.getRect(find.byType(ArxaKitNativeFloatingBar)).top,
        lessThan(0),
        reason: 'hide slid the whole bar off the top');
    expect(tester.getRect(find.byType(ArxaKitTopEdgeScrim)), resting,
        reason: 'the scrim must NOT ride the whole-bar slide — with the bar '
            'hidden it is the only thing between full-bleed content and the '
            'Dynamic Island');
  });

  testWidgets(
      'kit.ui-library.top-edge-scrim — draws with a gradient fill, adding no '
      'saveLayer and no alpha over the content', (tester) async {
    await tester.pumpWidget(scrimHarness());
    final scrim = find.byType(ArxaKitTopEdgeScrim);
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
    expect(gradient.stops![1],
        statusBar / (statusBar + kArxaKitFloatingBarBlockHeight),
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
                  child: ArxaKitTopEdgeScrim(fadeExtent: ramp)),
            ],
          ),
        ),
      ),
    ));

    expect(tester.getSize(find.byType(ArxaKitTopEdgeScrim)).height,
        statusBar + ramp,
        reason: 'the scrim ends where the host content begins');

    final gradient = (tester
            .widget<Container>(find
                .descendant(
                    of: find.byType(ArxaKitTopEdgeScrim),
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
        body: ArxaKitFloatingChrome(
          title: 'T',
          body: Builder(builder: (context) {
            seen = MediaQuery.paddingOf(context).top;
            return const SizedBox();
          }),
        ),
      ),
    ));
    expect(seen, kArxaKitFloatingBarBlockHeight,
        reason: 'test env has no status bar, so the raise IS the block');
  });

  // ---------------------------------------------------------------------
  // ArxaKitBottomEdgeScrim — the bottom-edge mirror. The per-child scroll
  // edge effect is deliberately inert on the glass tier (alpha over platform
  // views), so this gradient is the ONLY bottom dissolve on device (clip
  // 18-50). Same shape law as the top scrim: gradient fill, no saveLayer.
  // ---------------------------------------------------------------------

  const homeInset = 34.0;

  Widget bottomScrimHarness({bool enabled = true}) => MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewPadding: const EdgeInsets.only(bottom: homeInset),
            ),
            child: ArxaKitBottomEdgeScrimHost(
              enabled: enabled,
              child: ListView(
                children: [
                  for (var i = 0; i < 30; i++)
                    SizedBox(height: 80, key: Key('b$i')),
                ],
              ),
            ),
          ),
        ),
      );

  testWidgets(
      'kit.ui-library.bottom-edge-scrim — pins to the physical bottom edge '
      'and spans the home-indicator inset plus the fade ramp', (tester) async {
    await tester.pumpWidget(bottomScrimHarness());

    final scrim = tester.getRect(find.byType(ArxaKitBottomEdgeScrim));
    final screen = tester.getRect(find.byType(ArxaKitBottomEdgeScrimHost));
    expect(scrim.bottom, screen.bottom,
        reason: 'the dissolve ends at the physical bottom');
    expect(scrim.height, homeInset + kArxaKitFloatingBarBlockHeight,
        reason: 'opaque through the indicator band, ramp across the bar row');
  });

  testWidgets(
      'kit.ui-library.bottom-edge-scrim — gradient is clear at its top and '
      'opaque across the whole indicator band', (tester) async {
    await tester.pumpWidget(bottomScrimHarness());

    final gradient = (tester
            .widget<Container>(find
                .descendant(
                    of: find.byType(ArxaKitBottomEdgeScrim),
                    matching: find.byType(Container))
                .first)
            .decoration as BoxDecoration)
        .gradient! as LinearGradient;
    expect(gradient.colors.first.a, 0.0,
        reason: 'content above the ramp must be untouched');
    expect(gradient.colors.last.a, 1.0,
        reason: 'fully opaque at the physical edge — the hard-clip fix');
    expect(
        gradient.stops![1],
        kArxaKitFloatingBarBlockHeight /
            (homeInset + kArxaKitFloatingBarBlockHeight),
        reason: 'the ramp finishes where the indicator band begins');
  });

  testWidgets(
      'kit.ui-library.bottom-edge-scrim — never intercepts taps and the '
      'toggle removes it entirely', (tester) async {
    await tester.pumpWidget(bottomScrimHarness());
    expect(
        find.descendant(
            of: find.byType(ArxaKitBottomEdgeScrim),
            matching: find.byType(IgnorePointer)),
        findsOneWidget,
        reason: 'a decorative band must not eat scrolls/taps over the bar');

    await tester.pumpWidget(bottomScrimHarness(enabled: false));
    expect(find.byType(ArxaKitBottomEdgeScrim), findsNothing,
        reason: 'enabled:false is a design opt-out, not an invisible scrim');
  });

  testWidgets(
      'kit.ui-library.bottom-edge-scrim — steering enabled at runtime must '
      'not remount the child subtree', (tester) async {
    // C4 class (recorded in the showcase tab host): a build whose output
    // SHAPE changes with a flag remounts everything below it — nested
    // routers lose their stacks mid-push and the push is dropped on the
    // floor. `enabled` exists so a route can opt out, i.e. it is steered at
    // RUNTIME by hosts that yield the bottom edge per-route, so the host
    // must swap only its own scrim child and keep the body's slot stable.
    Widget harness({required bool enabled}) => MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                viewPadding: const EdgeInsets.only(bottom: homeInset),
              ),
              child: ArxaKitBottomEdgeScrimHost(
                enabled: enabled,
                child: ListView(
                  children: const [SizedBox(height: 80, key: Key('probe'))],
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(harness(enabled: true));
    final Element probe = tester.element(find.byKey(const Key('probe')));

    await tester.pumpWidget(harness(enabled: false));
    expect(find.byType(ArxaKitBottomEdgeScrim), findsNothing,
        reason: 'the opt-out still opts out');
    expect(tester.element(find.byKey(const Key('probe'))), same(probe),
        reason: 'a flag flip that remounts the body drops nested-router '
            'stacks mid-push (C4) — the yield use-case steers this flag at '
            'runtime');

    await tester.pumpWidget(harness(enabled: true));
    expect(find.byType(ArxaKitBottomEdgeScrim), findsOneWidget,
        reason: 're-enabling restores the scrim');
    expect(tester.element(find.byKey(const Key('probe'))), same(probe),
        reason: 're-enabling must be shape-stable too');
  });
}
