import 'package:flutter/material.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:ui_library/ui_library.dart';

/// Nested scope with an explicit controller driver — wake/set-down replayed
/// on demand, independent of the route animation above it.
class ShowcaseMotionManualReplayCardWidget extends StatefulWidget {
  const ShowcaseMotionManualReplayCardWidget({required this.spec, super.key});

  final KitMotionSpec spec;

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
