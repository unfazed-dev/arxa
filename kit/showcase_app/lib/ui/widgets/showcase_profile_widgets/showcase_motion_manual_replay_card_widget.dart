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
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// Nested scope with an explicit controller driver — wake/set-down replayed
/// on demand, independent of the route animation above it.
class ShowcaseMotionManualReplayCardWidget extends StatefulWidget {
  const ShowcaseMotionManualReplayCardWidget({required this.spec, super.key});

  final AppBoxKitMotionSpec spec;

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
        // AppBoxKitWake wraps the card INSIDE the Expanded — wakeAll() on the Row's
        // children list put the Fade/Slide transition between the Row and
        // each Expanded, breaking the FlexParentData contract (ParentDataWidget
        // assertion on route push).
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
    return AppBoxKitMotionScope(
      driver: _controller,
      spec: widget.spec,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: <Widget>[
              _chip(context, 'One', 0),
              appBoxKitHorizontalSpace(abxSize16 / 2),
              _chip(context, 'Two', 1),
              appBoxKitHorizontalSpace(abxSize16 / 2),
              _chip(context, 'Three', 2),
            ],
          ),
          appBoxKitVerticalSpaceSmall,
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppBoxKitNativeButton(
                label: 'Set down',
                onPressed: () => _controller.reverse(),
              ),
              appBoxKitHorizontalSpace(abxSize16 / 2),
              AppBoxKitNativeButton(
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
