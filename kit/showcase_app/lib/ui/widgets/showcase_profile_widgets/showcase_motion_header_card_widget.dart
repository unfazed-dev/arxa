import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// Header card explaining the route-driven wake demo.
class ShowcaseMotionHeaderCardWidget extends StatelessWidget {
  const ShowcaseMotionHeaderCardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBoxKitGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(axSize16),
        child: Text(
          'This screen woke under the route\'s own animation — no '
          'controller in the view. Pop with the edge-swipe and watch '
          'the choreography run backwards under your finger.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
