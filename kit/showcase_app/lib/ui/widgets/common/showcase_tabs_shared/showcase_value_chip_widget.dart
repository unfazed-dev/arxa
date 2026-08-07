/// A widget is a reusable UI building block: props in via the constructor,
/// widgets out via `build`. It never owns business logic.
///
/// This is the user interface for a small live-value pill shown beside a slider
/// label — tabular figures keep the digits from jittering while dragging.
///
/// Requirements:
/// 1. [Value chip] — profile-and-gallery-demos.gallery.browse-the-components-gallery
/// Shows the current value beside a slider so it stays visible while dragging.
///
/// Relationships:
///
///       ┌───────────────────┐
///       │ value chip widget │
///       └───────────────────┘
///    ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/common/showcase_tabs_shared/showcase_value_chip_widget.dart
library;

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
        borderRadius: BorderRadius.circular(abxRad10),
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
