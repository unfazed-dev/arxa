import 'package:flutter/material.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:ui_library/ui_library.dart';

/// Drag-scrubbed choreography: a [KitGestureDriver] maps the horizontal drag
/// to the scope's 0→1 timeline (wake-choreographed chips + a scrubbing
/// handle), and release settles with a [KitSprings] preset — the same driver
/// `KitDrawer` consumes for custom open/close choreography.
class ShowcaseMotionDragScrubCardWidget extends StatefulWidget {
  const ShowcaseMotionDragScrubCardWidget({required this.spec, super.key});

  final KitMotionSpec spec;

  @override
  State<ShowcaseMotionDragScrubCardWidget> createState() =>
      _ShowcaseMotionDragScrubCardState();
}

class _ShowcaseMotionDragScrubCardState
    extends State<ShowcaseMotionDragScrubCardWidget>
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
        // Same Expanded-inside-wake rule as ShowcaseMotionManualReplayCardWidget.
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
