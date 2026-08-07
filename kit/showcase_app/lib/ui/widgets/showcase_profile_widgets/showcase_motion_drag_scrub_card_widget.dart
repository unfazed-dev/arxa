/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the gesture-driver demo — a card whose
/// horizontal drag scrubs a motion scope's 0→1 timeline and settles with a
/// spring on release.
///
/// Requirements:
/// 1. [Gesture driver] — view-the-motion-demo
/// A horizontal drag scrubs the scope's timeline; release settles with a spring.
///
/// Relationships: a self-contained presentational widget — no viewmodel
/// binding; the spec is passed in, the gesture driver is local.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_motion_drag_scrub_card_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// Drag-scrubbed choreography: a [AppBoxKitGestureDriver] maps the horizontal drag
/// to the scope's 0→1 timeline (wake-choreographed chips + a scrubbing
/// handle), and release settles with a [AppBoxKitSprings] preset — the same driver
/// `AppBoxKitDrawer` consumes for custom open/close choreography.
class ShowcaseMotionDragScrubCardWidget extends StatefulWidget {
  const ShowcaseMotionDragScrubCardWidget({required this.spec, super.key});

  final AppBoxKitMotionSpec spec;

  @override
  State<ShowcaseMotionDragScrubCardWidget> createState() =>
      _ShowcaseMotionDragScrubCardState();
}

class _ShowcaseMotionDragScrubCardState
    extends State<ShowcaseMotionDragScrubCardWidget>
    with SingleTickerProviderStateMixin {
  // The drawer-settle preset, passed explicitly so the demo names AppBoxKitSprings
  // (it is also the driver's default).
  late final AppBoxKitGestureDriver _driver = AppBoxKitGestureDriver(
    vsync: this,
    settleSpring: AppBoxKitSprings.snappy,
  );

  @override
  void dispose() {
    _driver.dispose();
    super.dispose();
  }

  Widget _chip(BuildContext context, String label, int order) => Expanded(
        // Same Expanded-inside-wake rule as ShowcaseMotionManualReplayCardWidget.
        child: AppBoxKitGlassCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: abxSize16),
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
          child: AppBoxKitGlassCard(
            child: Padding(
              padding: const EdgeInsets.all(abxSize16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Drag this card horizontally: the drag scrubs the scope '
                    '0→1, release settles to the nearest end with '
                    'AppBoxKitSprings.snappy (re-grab mid-settle just works).',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  appBoxKitVerticalSpaceSmall,
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
                  appBoxKitVerticalSpaceSmall,
                  AppBoxKitMotionScope(
                    driver: _driver,
                    spec: widget.spec,
                    child: Row(
                      children: <Widget>[
                        _chip(context, 'One', 0),
                        appBoxKitHorizontalSpace(abxSize16 / 2),
                        _chip(context, 'Two', 1),
                        appBoxKitHorizontalSpace(abxSize16 / 2),
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
