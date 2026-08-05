import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

/// Section header used across the showcase tabs.
class ShowcaseSectionLabelWidget extends StatelessWidget {
  const ShowcaseSectionLabelWidget(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: KitColors.muted,
        ),
      );
}
