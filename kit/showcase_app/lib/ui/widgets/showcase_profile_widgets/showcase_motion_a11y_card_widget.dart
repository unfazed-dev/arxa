import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// Accessibility note card: reduce-motion (or the master switch) renders
/// every scope settled with no consuming-view changes.
class ShowcaseMotionA11yCardWidget extends StatelessWidget {
  const ShowcaseMotionA11yCardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBoxKitGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(axSize16),
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
