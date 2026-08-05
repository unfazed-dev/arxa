import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

/// Header card explaining the route-driven wake demo.
class ShowcaseMotionHeaderCardWidget extends StatelessWidget {
  const ShowcaseMotionHeaderCardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return KitGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(kSize16),
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
