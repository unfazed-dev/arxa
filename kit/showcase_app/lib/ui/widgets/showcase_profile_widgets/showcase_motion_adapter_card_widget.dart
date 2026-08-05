import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:ui_library/ui_library.dart';

/// flutter_animate adapter demo: a plain `.animate()` chain whose timeline
/// comes from the enclosing [KitMotionScope] via [KitMotionAdapter]. Must be
/// placed under a scope — its own context is passed to
/// `KitMotionAdapter.of`.
class ShowcaseMotionAdapterCardWidget extends StatelessWidget {
  const ShowcaseMotionAdapterCardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return KitGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(kSize16),
        child: Text(
          'This card animates through a plain flutter_animate '
          'chain, but its timeline comes from the scope via '
          'KitMotionAdapter — same driver, same scrub, same '
          'reduce-motion handling.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    )
        .animate(adapter: KitMotionAdapter.of(context))
        .fadeIn()
        .slideY(begin: 0.08, end: 0);
  }
}
