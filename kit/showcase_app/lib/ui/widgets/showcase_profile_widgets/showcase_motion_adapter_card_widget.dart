/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the flutter_animate adapter demo — a card
/// whose plain animate chain takes its timeline from the enclosing motion
/// scope via ArxaKitMotionAdapter.
///
/// Requirements:
/// 1. [flutter_animate adapter] — view-the-motion-demo
/// A plain animate chain driven by the enclosing scope's timeline.
///
/// Relationships: a self-contained presentational widget — no viewmodel
/// binding; reads the scope from its own context.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_motion_adapter_card_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:arxa_kit_motion/arxa_kit_motion.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

class ShowcaseMotionAdapterCardWidget extends StatelessWidget {
  const ShowcaseMotionAdapterCardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ArxaKitGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(abxSize16),
        child: Text(
          'This card animates through a plain flutter_animate '
          'chain, but its timeline comes from the scope via '
          'ArxaKitMotionAdapter — same driver, same scrub, same '
          'reduce-motion handling.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    )
        .animate(adapter: ArxaKitMotionAdapter.of(context))
        .fadeIn()
        .slideY(begin: 0.08, end: 0);
  }
}
