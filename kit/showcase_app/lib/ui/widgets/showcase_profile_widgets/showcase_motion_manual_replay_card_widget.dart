/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the manual-replay demo — a nested motion
/// scope with its own controller driver, replayable on demand.
///
/// Requirements:
/// 1. [Manual replay] — view-the-motion-demo
/// A nested scope replays wake/set-down on demand via set-down and replay buttons.
///
/// Relationships: a self-contained presentational widget — no viewmodel
/// binding; the spec is passed in, the controller is local.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_motion_manual_replay_card_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_motion/arxa_kit_motion.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

class ShowcaseMotionManualReplayCardWidget extends StatefulWidget {
  const ShowcaseMotionManualReplayCardWidget({required this.spec, super.key});

  final ArxaKitMotionSpec spec;

  @override
  State<ShowcaseMotionManualReplayCardWidget> createState() =>
      _ShowcaseMotionManualReplayCardState();
}

class _ShowcaseMotionManualReplayCardState
    extends State<ShowcaseMotionManualReplayCardWidget>
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
        // ArxaKitWake wraps the card INSIDE the Expanded — wakeAll() on the Row's
        // children list put the Fade/Slide transition between the Row and
        // each Expanded, breaking the FlexParentData contract (ParentDataWidget
        // assertion on route push).
        child: ArxaKitGlassCard(
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
    return ArxaKitMotionScope(
      driver: _controller,
      spec: widget.spec,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: <Widget>[
              _chip(context, 'One', 0),
              arxaKitHorizontalSpace(abxSize16 / 2),
              _chip(context, 'Two', 1),
              arxaKitHorizontalSpace(abxSize16 / 2),
              _chip(context, 'Three', 2),
            ],
          ),
          arxaKitVerticalSpaceSmall,
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ArxaKitNativeButton(
                label: 'Set down',
                onPressed: () => _controller.reverse(),
              ),
              arxaKitHorizontalSpace(abxSize16 / 2),
              ArxaKitNativeButton(
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
