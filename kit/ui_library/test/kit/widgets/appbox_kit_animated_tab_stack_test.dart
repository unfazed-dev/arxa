import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_animated_tab_stack.dart';

// AppBoxKitAnimatedTabStack owns its tab bodies: each must be inflated exactly once
// (lazily, on first visit) and then keep its State across switches — including
// the two reparent moves (base layer → exit slot → base layer) every switch
// puts the outgoing tab through. This records every State creation per label.
final _inits = <String>[];

class _Probe extends StatefulWidget {
  const _Probe(this.label, {super.key});

  final String label;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int taps = 0;

  @override
  void initState() {
    super.initState();
    _inits.add(widget.label);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => taps++),
      child: Text('${widget.label}:$taps'),
    );
  }
}

Widget _frame(int index,
    {bool fade = false,
    int childCount = 3,
    Color? backgroundColor,
    bool? animated}) {
  // Fresh widget instances every build — the same contract
  // StackedTabsRouter.builder's regenerated `children` list has: state must
  // bind to the slot, never to the instance.
  return Directionality(
    textDirection: TextDirection.ltr,
    child: AppBoxKitAnimatedTabStack(
      activeIndex: index,
      fade: fade,
      animated: animated,
      backgroundColor: backgroundColor,
      children: [
        for (var i = 0; i < childCount; i++) _Probe('tab$i', key: ValueKey(i)),
      ],
    ),
  );
}

// Finders: the default `skipOffstage: true` means "on the stage" — exactly the
// distinction these tests assert. A settled outgoing tab is GONE from the
// stage (default finder finds nothing) while still KEPT ALIVE (skipOffstage:
// false finds it once, under its Offstage).
Finder _onStage(String text) => find.textContaining(text);
Finder _alive(String text) => find.textContaining(text, skipOffstage: false);

List<double> _slideDxs(WidgetTester tester) => tester
    .widgetList<SlideTransition>(find.byType(SlideTransition))
    .map((s) => s.position.value.dx)
    .toList();

// The instant (iOS cross-cut) path hides visited tabs by near-zero alpha
// instead of offstaging them, so this reads the slot Opacity above a tab.
double _opacityOf(WidgetTester tester, String text) => tester
    .widget<Opacity>(find.ancestor(
      of: find.textContaining(text, skipOffstage: false),
      matching: find.byType(Opacity),
    ))
    .opacity;

void main() {
  setUp(_inits.clear);

  testWidgets(
      'kit.ui-library.animated-tab-stack — lazy kept-alive: unvisited tabs cost nothing, idle frames '
      'render exactly one tab', (tester) async {
    await tester.pumpWidget(_frame(0));
    expect(_onStage('tab0'), findsOneWidget);
    expect(_alive('tab1'), findsNothing,
        reason: 'unvisited tabs are never inflated');
    expect(_alive('tab2'), findsNothing);
    expect(_inits, ['tab0']);
    final visible = tester
        .widgetList<Offstage>(find.byType(Offstage))
        .where((o) => !o.offstage);
    expect(visible, hasLength(1),
        reason: 'idle frames render the active tab only');
  });

  testWidgets(
      'kit.ui-library.animated-tab-stack — paired transition: the outgoing tab slides out while the '
      'incoming slides in, then leaves the stage', (tester) async {
    await tester.pumpWidget(_frame(0));
    await tester.pumpWidget(_frame(1)); // forward switch starts
    await tester.pump(const Duration(milliseconds: 50)); // mid-flight

    // Both tabs on stage, each EXACTLY once — zero duplicate inflation.
    expect(_onStage('tab0'), findsOneWidget);
    expect(_onStage('tab1'), findsOneWidget);

    // Same controller run: one slide is positive (incoming from the trailing
    // edge, LTR forward), the other negative (outgoing through the leading
    // edge) — and the outgoing tab is the one translating away.
    final dxs = _slideDxs(tester);
    expect(dxs.where((d) => d > 0), hasLength(1),
        reason: 'incoming tab slides in from the trailing edge');
    expect(dxs.where((d) => d < 0), hasLength(1),
        reason: 'outgoing tab slides out through the leading edge');
    final tab0Slide = tester.widget<SlideTransition>(find.ancestor(
      of: _onStage('tab0'),
      matching: find.byType(SlideTransition),
    ));
    expect(tab0Slide.position.value.dx, lessThan(0),
        reason: 'tab0 is the outgoing tab');

    await tester.pump(const Duration(milliseconds: 300)); // settle

    // Gone from the stage, kept alive underneath, no residual motion, and
    // never re-inflated despite the two reparent moves.
    expect(_onStage('tab0'), findsNothing,
        reason: 'the outgoing tab leaves the stage when the exit settles');
    expect(_alive('tab0'), findsOneWidget,
        reason: '...but stays mounted (kept alive)');
    expect(_onStage('tab1'), findsOneWidget);
    final tab0Offstage = tester.widget<Offstage>(find.ancestor(
      of: _alive('tab0'),
      matching: find.byType(Offstage),
    ));
    expect(tab0Offstage.offstage, isTrue);
    final activeSlide = tester.widget<SlideTransition>(find.ancestor(
      of: _onStage('tab1'),
      matching: find.byType(SlideTransition),
    ));
    expect(activeSlide.position.value, Offset.zero,
        reason: 'the incoming tab settles home');
    expect(_inits.where((l) => l == 'tab0'), hasLength(1),
        reason: 'reparented through the exit, never re-inflated');
  });

  testWidgets('kit.ui-library.animated-tab-stack — direction helper: backward switch mirrors both slides',
      (tester) async {
    await tester.pumpWidget(_frame(0));
    await tester.pumpWidget(_frame(2)); // forward, then let it settle
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(_frame(0)); // backward
    await tester.pump(const Duration(milliseconds: 50));
    final dxs = _slideDxs(tester);
    expect(dxs.where((d) => d < 0), hasLength(1),
        reason: 'backward switch: incoming from the leading edge');
    expect(dxs.where((d) => d > 0), hasLength(1),
        reason: 'backward switch: outgoing through the trailing edge');
  });

  testWidgets('kit.ui-library.animated-tab-stack — no phantom motion before the first switch', (tester) async {
    await tester.pumpWidget(_frame(0));
    for (final dx in _slideDxs(tester)) {
      expect(dx, 0.0, reason: 'startup parks the controller at 1.0');
    }
  });

  testWidgets(
      'kit.ui-library.animated-tab-stack — keyed child keeps state across switches (tap survives the '
      'round trip)', (tester) async {
    await tester.pumpWidget(_frame(0));
    await tester.tap(find.text('tab0:0')); // mutate tab0's State
    await tester.pump();
    expect(find.text('tab0:1'), findsOneWidget);

    await tester.pumpWidget(_frame(1)); // away
    await tester.pump(const Duration(milliseconds: 300));
    expect(_alive('tab0'), findsOneWidget);
    expect(find.text('tab0:1', skipOffstage: false), findsOneWidget,
        reason: 'kept alive while hidden, state intact');

    await tester.pumpWidget(_frame(0)); // and back
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('tab0:1'), findsOneWidget,
        reason: 'state survives the round trip');
    expect(_inits.where((l) => l == 'tab0'), hasLength(1));
  });

  testWidgets(
      'kit.ui-library.animated-tab-stack — router-model shape: regenerated children list and same-index '
      'rebuilds stay quiet', (tester) async {
    // StackedTabsRouter.builder regenerates its children on every router
    // build, including builds where the index did NOT change — those must not
    // restart the transition or re-inflate anything.
    await tester.pumpWidget(_frame(0));
    await tester.pumpWidget(_frame(0));
    expect(_inits, ['tab0']);
    for (final dx in _slideDxs(tester)) {
      expect(dx, 0.0, reason: 'no index change, no motion');
    }
    // Placeholders for unvisited slots must never swallow the active tab's
    // taps (a bare box above it would).
    await tester.tap(find.text('tab0:0'));
    await tester.pump();
    expect(find.text('tab0:1'), findsOneWidget,
        reason: 'hit-transparent placeholders let taps through');
  });

  testWidgets(
      'kit.ui-library.animated-tab-stack — rapid reverse mid-flight reparents both ways without '
      'duplication or state loss', (tester) async {
    await tester.pumpWidget(_frame(0));
    await tester.pumpWidget(_frame(1)); // forward starts
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(_frame(0)); // reverse before the exit settled
    await tester.pump(const Duration(milliseconds: 50));

    // Never duplicated, never re-inflated — whichever slot each tab's live
    // element is in right now.
    expect(_alive('tab0'), findsOneWidget);
    expect(_alive('tab1'), findsOneWidget);
    expect(_inits.where((l) => l == 'tab0'), hasLength(1));
    expect(_inits.where((l) => l == 'tab1'), hasLength(1));

    await tester.pump(const Duration(milliseconds: 300)); // settle
    expect(_onStage('tab0'), findsOneWidget, reason: 'back on tab0');
    expect(_onStage('tab1'), findsNothing, reason: 'tab1 off the stage');
    expect(_alive('tab1'), findsOneWidget, reason: 'tab1 kept alive');
  });

  testWidgets('kit.ui-library.animated-tab-stack — tab-list shrink mid-exit cuts the exit short', (tester) async {
    // Live recomposition (the host's per-Session tab list) can remove the
    // leaving tab while its exit is still running.
    await tester.pumpWidget(_frame(2));
    await tester.pumpWidget(_frame(1)); // tab2 starts exiting
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(_frame(1, childCount: 2)); // tab2 vanishes
    await tester.pump(const Duration(milliseconds: 300));
    expect(_onStage('tab1'), findsOneWidget);
    expect(_alive('tab2'), findsNothing);
    expect(_inits.where((l) => l == 'tab2'), hasLength(1));
  });

  testWidgets(
      'kit.ui-library.animated-tab-stack — active tab vanishing with a shrink snaps to the clamped index '
      '(no out-of-range exit)', (tester) async {
    // The router-clamp path: a grant revoked while SITTING on its tab shrinks
    // the children and moves the index in the same update — there is no
    // leaving tab to animate out.
    await tester.pumpWidget(_frame(2));
    await tester.pumpWidget(_frame(0, childCount: 2)); // clamp 2 → 0
    await tester.pump(const Duration(milliseconds: 300));
    expect(_onStage('tab0'), findsOneWidget);
    expect(_alive('tab2'), findsNothing,
        reason: 'the removed tab is disposed, not kept');
    expect(_inits.where((l) => l == 'tab0'), hasLength(1));
  });

  testWidgets('kit.ui-library.animated-tab-stack — fade stays off by default (platform-view safety)',
      (tester) async {
    await tester.pumpWidget(_frame(0));
    expect(find.byType(FadeTransition), findsNothing,
        reason: 'opacity-animating platform-view subtrees ghosts '
            '(flutter#148639/#24164) — fade must be opt-in (check 1c2)');
  });

  testWidgets('kit.ui-library.animated-tab-stack — fade opt-in cross-fades the pair', (tester) async {
    await tester.pumpWidget(_frame(0, fade: true));
    expect(find.byType(FadeTransition), findsNWidgets(2),
        reason: 'incoming fades in, outgoing fades out — wrappers always '
            'present so the tree shape never changes with animation phase');
  });

  testWidgets(
      'kit.ui-library.animated-tab-stack — incoming layer carries the opaque '
      'backing only while a run is live (ghost occlusion)', (tester) async {
    const bg = Color(0xFFFFF8EE);
    // The single ColoredBox lives in the incoming layer (the exiting layer
    // never carries one — it is meant to be seen through to the scaffold).
    Color runColor() => tester
        .widget<ColoredBox>(find.descendant(
            of: find.byType(AppBoxKitAnimatedTabStack),
            matching: find.byType(ColoredBox)))
        .color;

    await tester.pumpWidget(_frame(0, backgroundColor: bg));
    expect(runColor().a, 0,
        reason: 'idle frames must stay transparent — a deliberately '
            'see-through stack composites over custom app backgrounds');

    await tester.pumpWidget(_frame(1, backgroundColor: bg));
    await tester.pump(const Duration(milliseconds: 100)); // mid-run
    expect(runColor(), bg,
        reason: 'background-less tab pages do not occlude by themselves: '
            'without the backing the outgoing tab reads through the incoming '
            'one for the whole run (the reported ghosting)');

    await tester.pump(const Duration(milliseconds: 300)); // settle
    expect(runColor().a, 0, reason: 'backing drops with the exit slot');
  });

  // `UITabBarController` cross-cuts between tabs — it has never slid, faded or
  // parallaxed — so instant is the native behaviour on iOS. It is also the only
  // shape that keeps ONE tab on stage per frame: an animated run paints both at
  // once, so the frame's platform-view set and z-order change mid-switch and the
  // iOS embedder recomposes overlays + merges the raster/platform threads. That
  // merge is the reported tab-switch flicker.
  //
  // Forced rather than inferred: this suite's host is macOS, where
  // `AppBoxKitPlatform.isIOS` reads `dart:io` and is false — which is also why
  // every test above still exercises the animated path unchanged.
  group('native cross-cut (iOS)', () {
    setUp(() => AppBoxKitPlatform.override =
        const AppBoxKitPlatformOverride(isIOS: true));
    tearDown(AppBoxKitPlatform.reset);

    testWidgets(
        'kit.ui-library.animated-tab-stack — a switch is an instant cross-cut: the outgoing tab is '
        'alpha-hidden in the SAME frame and never leaves the paint tree', (tester) async {
      await tester.pumpWidget(_frame(0));
      await tester.pumpWidget(_frame(1));

      // The UIKit `isHidden` equivalent: a visited tab stays IN the paint
      // tree at ~1/255 alpha instead of being offstaged. Leaving the paint
      // tree is what removeFromSuperviews its platform views — every
      // re-entry is an addSubview, and on iOS 26 every attach is a glass
      // materialize against a not-yet-composited backdrop (the bright-card
      // flash); the mid-switch platform-view-SET change is also what
      // recomposes overlays and ghosts the tab bar. Alpha-hiding keeps the
      // set constant, so neither happens.
      expect(_opacityOf(tester, 'tab0'), inInclusiveRange(0.0001, 0.01),
          reason: 'the outgoing tab hides at ~1/255 alpha, still painted');
      expect(_opacityOf(tester, 'tab1'), 1.0,
          reason: 'the incoming tab is fully visible in the same frame');
      expect(find.byType(Offstage), findsNothing,
          reason: 'the instant path never offstages a visited tab');
      expect(
          tester
              .widget<IgnorePointer>(find.ancestor(
                of: _alive('tab0'),
                matching: find.byType(IgnorePointer),
              ))
              .ignoring,
          isTrue,
          reason: 'the hidden tab must not take the active tab\'s taps');
      expect(
          tester
              .widget<ExcludeSemantics>(find.ancestor(
                of: _alive('tab0'),
                matching: find.byType(ExcludeSemantics),
              ))
              .excluding,
          isTrue,
          reason: 'an invisible tab is not in the semantics tree');
      for (final dx in _slideDxs(tester)) {
        expect(dx, 0.0, reason: 'no controller run, so nothing translates');
      }

      // Back again: the same element returns to full alpha — no re-inflate.
      await tester.pumpWidget(_frame(0));
      expect(_opacityOf(tester, 'tab0'), 1.0,
          reason: 'a re-visited tab is an alpha flip, not a re-attach');
      expect(_inits, ['tab0', 'tab1'],
          reason: 'alpha-hide keeps the element mounted; nothing re-inflates');
    });

    testWidgets(
        'kit.ui-library.animated-tab-stack — a hidden tab is paint-clipped to a '
        'sub-pixel window (ghost containment)', (tester) async {
      // Alpha alone is not containment: a hidden tab still paints every
      // frame, and its platform views slice the ACTIVE tab's frame into
      // overlay textures. On device (recordings 2026-08-12) pieces of those
      // hidden subtrees composited over the active tab at visible alpha — a
      // stale white rail-pane rectangle over Profile, a "Maps showcase"
      // ghost and white slab over Search's options section. The clip keeps
      // the alpha-hide's native-hierarchy guarantee (paint still happens, so
      // the platform views never detach) while bounding EVERYTHING a hidden
      // tab can contribute to the frame to half a pixel.
      await tester.pumpWidget(_frame(0));
      await tester.pumpWidget(_frame(1));

      ClipRect clipOf(String text) => tester.widget<ClipRect>(find.ancestor(
            of: find.textContaining(text, skipOffstage: false),
            matching: find.byType(ClipRect),
          ));

      final hidden = clipOf('tab0');
      expect(hidden.clipBehavior, Clip.hardEdge,
          reason: 'the hidden tab must actually clip');
      final rect = hidden.clipper!.getClip(const Size(390, 844));
      expect(rect.width, lessThanOrEqualTo(1.0),
          reason: 'sub-pixel window: nothing legible can ghost through');
      expect(rect.height, lessThanOrEqualTo(1.0));
      expect(rect.isEmpty, isFalse,
          reason: 'non-degenerate on purpose — a fully-empty clip risks the '
              'engine culling the platform views out of the composition, '
              'which is the re-attach flash the alpha-hide exists to avoid');

      final active = clipOf('tab1');
      expect(active.clipBehavior, Clip.none,
          reason: 'the active tab pays no clip layer (constant-shape rule: '
              'the wrapper stays mounted, driven to identity)');
      expect(active.clipper, isNull,
          reason: 'clipBehavior only gates PAINT clipping — '
              'RenderClipRect.hitTest consults the clipper even at Clip.none, '
              'so a sub-pixel clipper here swallows every tap in the app');

      // Behavioral proof: a tap on the active tab must still land.
      await tester.tap(find.text('tab1:0'));
      await tester.pump();
      expect(find.text('tab1:1'), findsOneWidget,
          reason: 'the active tab keeps full hit-test coverage');
    });

    testWidgets(
        'kit.ui-library.animated-tab-stack — instant keeps the kept-alive contract (state survives '
        'the round trip)', (tester) async {
      await tester.pumpWidget(_frame(0));
      await tester.tap(find.text('tab0:0'));
      await tester.pump();

      await tester.pumpWidget(_frame(1)); // away
      await tester.pumpWidget(_frame(0)); // and straight back
      expect(find.text('tab0:1'), findsOneWidget,
          reason: 'instant must not cost the state the animation preserved');
      expect(_inits.where((l) => l == 'tab0'), hasLength(1));
    });

    testWidgets(
        'kit.ui-library.animated-tab-stack — animated: true forces the paired slide back on '
        '(escape hatch)', (tester) async {
      await tester.pumpWidget(_frame(0, animated: true));
      await tester.pumpWidget(_frame(1, animated: true));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_onStage('tab0'), findsOneWidget);
      expect(_onStage('tab1'), findsOneWidget);
      expect(_slideDxs(tester).where((d) => d != 0), isNotEmpty,
          reason: 'an explicit true opts back into the non-native affordance');
    });
  });

  testWidgets(
      'kit.ui-library.animated-tab-stack — switching to instant WHILE a run is in flight lands '
      'cleanly (the one path that parks the controller)', (tester) async {
    // `_controller.value = 1.0` executes ONLY here: a run is live — so the
    // SlideTransitions are active listeners, notified from inside
    // didUpdateWidget — and a new index arrives with animation now off. The
    // steady path is guarded out by `isCompleted`, so this is the case where
    // the notify-during-build reasoning actually has to hold.
    await tester.pumpWidget(_frame(0, animated: true));
    await tester.pumpWidget(_frame(1, animated: true));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_onStage('tab0'), findsOneWidget, reason: 'a run really is in flight');

    await tester.pumpWidget(_frame(2, animated: false));
    expect(tester.takeException(), isNull,
        reason: 'notifying live listeners from didUpdateWidget must not throw');
    expect(_opacityOf(tester, 'tab2'), 1.0);
    expect(_opacityOf(tester, 'tab0'), lessThan(0.01),
        reason: 'the interrupted exit lands alpha-hidden');
    expect(_opacityOf(tester, 'tab1'), lessThan(0.01));
    expect(_alive('tab0'), findsOneWidget, reason: 'both stay kept alive');
    expect(_alive('tab1'), findsOneWidget);
    for (final dx in _slideDxs(tester)) {
      expect(dx, 0.0,
          reason: 'parked at the identity end-state, exit slot included');
    }
  });

  testWidgets(
      'kit.ui-library.animated-tab-stack — animated: false forces the cross-cut off-iOS too',
      (tester) async {
    await tester.pumpWidget(_frame(0, animated: false));
    await tester.pumpWidget(_frame(1, animated: false));
    expect(_opacityOf(tester, 'tab0'), lessThan(0.01),
        reason: 'outgoing tab alpha-hidden, not offstaged');
    expect(_opacityOf(tester, 'tab1'), 1.0);
    for (final dx in _slideDxs(tester)) {
      expect(dx, 0.0);
    }
  });
}
