/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the accessibility note — a card explaining
/// that reduce-motion (or the master switch off) renders every scope settled.
///
/// Requirements:
/// 1. [Accessibility] — view-the-motion-demo
/// A card noting reduce-motion renders every scope settled with no view changes.
///
/// Relationships: a self-contained presentational widget — no viewmodel
/// binding; static explanatory text.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_motion_a11y_card_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

class ShowcaseMotionA11yCardWidget extends StatelessWidget {
  const ShowcaseMotionA11yCardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBoxKitGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(abxSize16),
        child: Text(
          'With OS reduce-motion on (or the switch above off), every '
          'scope renders its children settled — no code changes in '
          'the consuming view.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
