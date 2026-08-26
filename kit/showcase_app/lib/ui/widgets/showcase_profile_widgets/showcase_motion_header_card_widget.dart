/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the motion header — a card explaining the
/// route-driven wake demo.
///
/// Requirements:
/// 1. [Route-driven wake] — view-the-motion-demo
/// A header card explaining that the screen woke under the route's own animation.
///
/// Relationships: a self-contained presentational widget — no viewmodel
/// binding; static explanatory text.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_motion_header_card_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

/// Header card explaining the route-driven wake demo.
class ShowcaseMotionHeaderCardWidget extends StatelessWidget {
  const ShowcaseMotionHeaderCardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ArxaKitGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(abxSize16),
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
