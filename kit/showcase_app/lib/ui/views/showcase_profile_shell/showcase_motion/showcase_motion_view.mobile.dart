import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:stacked/stacked.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/common/showcase_tabs_shared.dart';

import 'showcase_motion_viewmodel.dart';

/// Motion showcase — every appbox_kit_motion feature on one pushed surface:
///
/// * **Route-driven wake**: the whole screen sits under a [KitMotionScope]
///   with no explicit driver, so the route's push animation *is* the
///   timeline — content wakes as the page arrives, and the iOS swipe-back
///   gesture scrubs the set-down in reverse.
/// * **Spec presets + master switch**: the segmented control swaps
///   [KitMotionSpec] presets; the switch flips `enabled` (everything renders
///   settled when off — same behavior reduce-motion triggers automatically).
/// * **Manual replay**: a nested scope with its own controller driver,
///   replayable on demand.
/// * **flutter_animate adapter**: [KitMotionAdapter] hands the scope's
///   timeline to a plain `.animate()` chain.
class ShowcaseMotionViewMobile
    extends ViewModelWidget<ShowcaseMotionViewModel> {
  const ShowcaseMotionViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseMotionViewModel viewModel) {
    return Scaffold(
      appBar: KitNativeAppBar(
        leading: KitNativeIconButton(
          glyph: KitGlyphs.back,
          onPressed: () => context.popRoute(),
        ),
        title: 'Motion',
      ),
      body: KitMotionScope(
        // No driver: adopts the enclosing route's animation. Push plays the
        // wake; iOS swipe-back scrubs the set-down interactively.
        spec: viewModel.spec,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(kSize16, kSize16, kSize16, 120),
          children: <Widget>[
            KitGlassCard(
              child: Padding(
                padding: const EdgeInsets.all(kSize16),
                child: Text(
                  'This screen woke under the route\'s own animation — no '
                  'controller in the view. Pop with the edge-swipe and watch '
                  'the choreography run backwards under your finger.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            verticalSpaceMedium,
            const ShowcaseSectionLabel('Spec presets'),
            verticalSpaceSmall,
            KitNativeSegmentedControl(
              segments: ShowcaseMotionViewModel.presetLabels,
              selectedIndex: viewModel.presetIndex,
              onChanged: viewModel.setPreset,
            ),
            verticalSpaceSmall,
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Motion enabled',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                KitNativeSwitch(
                  value: viewModel.enabled,
                  onChanged: viewModel.setEnabled,
                  semanticLabel: 'Motion enabled',
                ),
              ],
            ),
            verticalSpaceMedium,
            const ShowcaseSectionLabel('Manual replay'),
            verticalSpaceSmall,
            _ManualReplayCard(spec: viewModel.spec),
            verticalSpaceMedium,
            const ShowcaseSectionLabel('flutter_animate adapter'),
            verticalSpaceSmall,
            Builder(
              builder: (context) => KitGlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(kSize16),
                  child: Text(
                    'This card animates through a plain flutter_animate '
                    'chain, but its timeline comes from the scope via '
                    'KitMotionAdapter — same driver, same scrub, same '
                    'reduce-motion handling.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
                  .animate(adapter: KitMotionAdapter.of(context))
                  .fadeIn()
                  .slideY(begin: 0.08, end: 0),
            ),
            verticalSpaceMedium,
            const ShowcaseSectionLabel('Gesture driver + springs'),
            verticalSpaceSmall,
            _DragScrubCard(spec: viewModel.spec),
            verticalSpaceMedium,
            const ShowcaseSectionLabel('Accessibility'),
            verticalSpaceSmall,
            KitGlassCard(
              child: Padding(
                padding: const EdgeInsets.all(kSize16),
                child: Text(
                  'With OS reduce-motion on (or the switch above off), every '
                  'scope renders its children settled — no code changes in '
                  'the consuming view.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ].wakeAll(),
        ),
      ),
    );
  }
}

/// Nested scope with an explicit controller driver — wake/set-down replayed
/// on demand, independent of the route animation above it.
class _ManualReplayCard extends StatefulWidget {
  const _ManualReplayCard({required this.spec});

  final KitMotionSpec spec;

  @override
  State<_ManualReplayCard> createState() => _ManualReplayCardState();
}

class _ManualReplayCardState extends State<_ManualReplayCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _chip(BuildContext context, String label, int order) => Expanded(
        // KitWake wraps the card INSIDE the Expanded — wakeAll() on the Row's
        // children list put the Fade/Slide transition between the Row and
        // each Expanded, breaking the FlexParentData contract (ParentDataWidget
        // assertion on route push).
        child: KitGlassCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: kSize16),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ).wake(order: order),
      );

  @override
  Widget build(BuildContext context) {
    return KitMotionScope(
      driver: _controller,
      spec: widget.spec,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: <Widget>[
              _chip(context, 'One', 0),
              horizontalSpace(kSize16 / 2),
              _chip(context, 'Two', 1),
              horizontalSpace(kSize16 / 2),
              _chip(context, 'Three', 2),
            ],
          ),
          verticalSpaceSmall,
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              KitNativeButton(
                label: 'Set down',
                onPressed: () => _controller.reverse(),
              ),
              horizontalSpace(kSize16 / 2),
              KitNativeButton(
                label: 'Replay',
                onPressed: () => _controller.forward(from: 0),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Drag-scrubbed choreography: a [KitGestureDriver] maps the horizontal drag
/// to the scope's 0→1 timeline (wake-choreographed chips + a scrubbing
/// handle), and release settles with a [KitSprings] preset — the same driver
/// `KitDrawer` consumes for custom open/close choreography.
class _DragScrubCard extends StatefulWidget {
  const _DragScrubCard({required this.spec});

  final KitMotionSpec spec;

  @override
  State<_DragScrubCard> createState() => _DragScrubCardState();
}

class _DragScrubCardState extends State<_DragScrubCard>
    with SingleTickerProviderStateMixin {
  // The drawer-settle preset, passed explicitly so the demo names KitSprings
  // (it is also the driver's default).
  late final KitGestureDriver _driver = KitGestureDriver(
    vsync: this,
    settleSpring: KitSprings.snappy,
  );

  @override
  void dispose() {
    _driver.dispose();
    super.dispose();
  }

  Widget _chip(BuildContext context, String label, int order) => Expanded(
        // Same Expanded-inside-wake rule as _ManualReplayCard above.
        child: KitGlassCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: kSize16),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ).wake(order: order),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Full card width maps to the full 0→1 progress — the caller owns
        // the drag→progress mapping, the driver owns scrub + settle.
        final extent = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) =>
              _driver.scrubBy(details.primaryDelta! / extent),
          onHorizontalDragEnd: (details) =>
              _driver.settle(velocity: (details.primaryVelocity ?? 0) / extent),
          child: KitGlassCard(
            child: Padding(
              padding: const EdgeInsets.all(kSize16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Drag this card horizontally: the drag scrubs the scope '
                    '0→1, release settles to the nearest end with '
                    'KitSprings.snappy (re-grab mid-settle just works).',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  verticalSpaceSmall,
                  // Scrub handle — its position IS the driver value.
                  Container(
                    height: 32,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: AnimatedBuilder(
                      animation: _driver,
                      builder: (context, child) => Align(
                        alignment: Alignment(-1 + 2 * _driver.value, 0),
                        child: child,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox(width: 28, height: 28),
                        ),
                      ),
                    ),
                  ),
                  verticalSpaceSmall,
                  KitMotionScope(
                    driver: _driver,
                    spec: widget.spec,
                    child: Row(
                      children: <Widget>[
                        _chip(context, 'One', 0),
                        horizontalSpace(kSize16 / 2),
                        _chip(context, 'Two', 1),
                        horizontalSpace(kSize16 / 2),
                        _chip(context, 'Three', 2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
