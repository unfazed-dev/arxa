import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// Small live-value pill shown beside a slider label so the current value is
/// visible while dragging. Tabular figures keep the digits from jittering.
class ShowcaseValueChipWidget extends StatelessWidget {
  const ShowcaseValueChipWidget(this.value, {super.key});

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(axRad10),
      ),
      child: Text(
        value,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
