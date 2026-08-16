import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// C4 — scroll-edge tree-shape stability (glass-chrome root-cause fixes).
///
/// The visible scroll-edge artifact is a *remount*, not the blur: returning
/// `widget.child` raw at `t == 0` and a 4-level wrapper at `t > 0` changes
/// the tree depth, so the child's Element — and any platform view inside it —
/// is destroyed and re-created at every threshold crossing. These tests pin
/// the three properties of the fix:
///
///  a. constant tree shape — the same State object survives crossings in
///     both directions;
///  b. hysteresis — scroll jitter around the legacy `t ≈ 0.02` boundary
///     causes at most one engagement flip;
///  c. first mount under chrome — the post-frame recompute must not remount
///     the child (exactly one initState);
///  d. at rest the chain is identity — no ImageFilterLayer (no saveLayer),
///     opacity 1.0, pointers pass through.
void main() {
  const effectKey = Key('effect');

  Widget harness({required ScrollController controller}) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          controller: controller,
          slivers: [
            const SliverAppBar(
              pinned: true,
              expandedHeight: 160,
              title: Text('Bar'),
            ),
            SliverToBoxAdapter(
              child: AppBoxKitScrollEdgeEffect(
                key: effectKey,
                child: const _ProbeChild(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 2000)),
          ],
        ),
      ),
    );
  }

  // Geometry (mirrors the sibling test file): child top sits at 160, the
  // collapsed pinned bar is kToolbarHeight (56), child height 48. Coverage
  // begins at pixels = 104; covered fraction = (56 - (160 - pixels)) / 48.
  // The legacy single boundary t = 0.02 sits at pixels ≈ 104.96.

  final probeFinder = find.byType(_ProbeChild, skipOffstage: false);

  bool blurActive(WidgetTester tester) =>
      tester.layers.whereType<ImageFilterLayer>().isNotEmpty;

  testWidgets(
      'kit.ui-library.scroll-edge-effect — c4a same State survives threshold '
      'crossings in both directions', (tester) async {
    _ProbeChildState.initCount = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller: controller));
    await tester.pump(); // post-frame recompute

    final before = tester.state<_ProbeChildState>(probeFinder);

    controller.jumpTo(128); // t = 0.5 — well past the threshold
    await tester.pump();
    expect(tester.state<_ProbeChildState>(probeFinder), same(before),
        reason: 'crossing into the effect must not remount the child');

    controller.jumpTo(0); // fully clear again
    await tester.pump();
    expect(tester.state<_ProbeChildState>(probeFinder), same(before),
        reason: 'crossing back out must not remount the child');
    expect(_ProbeChildState.initCount, 1);
  });

  testWidgets(
      'kit.ui-library.scroll-edge-effect — c4b jitter around t ≈ 0.02 flips '
      'engagement at most once (hysteresis dead band)', (tester) async {
    _ProbeChildState.initCount = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller: controller));
    await tester.pump();

    final before = tester.state<_ProbeChildState>(probeFinder);
    var engaged = blurActive(tester);
    expect(engaged, isFalse);

    // Oscillate across the legacy boundary (pixels ≈ 104.96): raw t swings
    // between ≈ 0.0146 and 0.025 — ordinary scroll jitter for a row resting
    // near pinned chrome.
    var flips = 0;
    const jitter = [105.2, 104.7, 105.2, 104.7, 105.2, 104.7];
    for (final px in jitter) {
      controller.jumpTo(px);
      await tester.pump();
      final now = blurActive(tester);
      if (now != engaged) {
        flips++;
        engaged = now;
      }
    }
    expect(flips, lessThanOrEqualTo(1),
        reason: 'a dead band must absorb jitter around a single boundary');

    // Once genuinely engaged, the same jitter must not release it.
    controller.jumpTo(110); // raw t = 0.125 — clearly engaged
    await tester.pump();
    expect(blurActive(tester), isTrue);
    for (final px in jitter) {
      controller.jumpTo(px);
      await tester.pump();
      expect(blurActive(tester), isTrue,
          reason: 'release only below the exit threshold, not inside the band');
    }

    expect(tester.state<_ProbeChildState>(probeFinder), same(before));
    expect(_ProbeChildState.initCount, 1);
  });

  testWidgets(
      'kit.ui-library.scroll-edge-effect — c4c first mount under chrome '
      'creates the child exactly once', (tester) async {
    _ProbeChildState.initCount = 0;
    final controller = ScrollController(initialScrollOffset: 128);
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller: controller));

    final before = tester.state<_ProbeChildState>(probeFinder);
    await tester.pump(); // post-frame recompute lands (t = 0.5)
    await tester.pump();

    expect(_ProbeChildState.initCount, 1,
        reason: 'no create → destroy → create on first mount under chrome');
    expect(tester.state<_ProbeChildState>(probeFinder), same(before));
    expect(blurActive(tester), isTrue,
        reason: 'the effect still engages for a child starting covered');
  });

  testWidgets(
      'kit.ui-library.scroll-edge-effect — c4d at rest the chain is identity: '
      'no filter layer, opacity 1.0, pointers pass', (tester) async {
    _ProbeChildState.initCount = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller: controller));
    await tester.pump();

    expect(blurActive(tester), isFalse,
        reason: 'sigma 0 must not push an ImageFilterLayer (no saveLayer)');

    Finder inEffect(Type type) => find.descendant(
          of: find.byKey(effectKey, skipOffstage: false),
          matching: find.byType(type, skipOffstage: false),
          skipOffstage: false,
        );
    expect(tester.widget<Opacity>(inEffect(Opacity)).opacity, 1.0);
    expect(tester.widget<IgnorePointer>(inEffect(IgnorePointer)).ignoring,
        isFalse);
  });
}

class _ProbeChild extends StatefulWidget {
  const _ProbeChild();

  @override
  State<_ProbeChild> createState() => _ProbeChildState();
}

class _ProbeChildState extends State<_ProbeChild> {
  static int initCount = 0;

  @override
  void initState() {
    super.initState();
    initCount++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox(height: 48, width: 48);
}
