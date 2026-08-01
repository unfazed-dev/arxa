import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_library/widgets/kit_animated_tab_stack.dart';

// KitAnimatedTabStack owns its tab bodies: each must be inflated exactly once
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

Widget _frame(int index, {bool fade = false, int childCount = 3}) {
  // Fresh widget instances every build — the same contract
  // StackedTabsRouter.builder's regenerated `children` list has: state must
  // bind to the slot, never to the instance.
  return Directionality(
    textDirection: TextDirection.ltr,
    child: KitAnimatedTabStack(
      activeIndex: index,
      fade: fade,
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

void main() {
  setUp(_inits.clear);

  testWidgets(
      'lazy kept-alive: unvisited tabs cost nothing, idle frames '
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
      'paired transition: the outgoing tab slides out while the '
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

  testWidgets('direction helper: backward switch mirrors both slides',
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

  testWidgets('no phantom motion before the first switch', (tester) async {
    await tester.pumpWidget(_frame(0));
    for (final dx in _slideDxs(tester)) {
      expect(dx, 0.0, reason: 'startup parks the controller at 1.0');
    }
  });

  testWidgets(
      'keyed child keeps state across switches (tap survives the '
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
      'router-model shape: regenerated children list and same-index '
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
      'rapid reverse mid-flight reparents both ways without '
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

  testWidgets('tab-list shrink mid-exit cuts the exit short', (tester) async {
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
      'active tab vanishing with a shrink snaps to the clamped index '
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

  testWidgets('fade stays off by default (platform-view safety)',
      (tester) async {
    await tester.pumpWidget(_frame(0));
    expect(find.byType(FadeTransition), findsNothing,
        reason: 'opacity-animating platform-view subtrees ghosts '
            '(flutter#148639/#24164) — fade must be opt-in (check 1c2)');
  });

  testWidgets('fade opt-in cross-fades the pair', (tester) async {
    await tester.pumpWidget(_frame(0, fade: true));
    expect(find.byType(FadeTransition), findsNWidgets(2),
        reason: 'incoming fades in, outgoing fades out — wrappers always '
            'present so the tree shape never changes with animation phase');
  });
}
