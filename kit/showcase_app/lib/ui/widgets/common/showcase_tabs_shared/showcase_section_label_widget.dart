/// A widget is a reusable UI building block: props in via the constructor,
/// widgets out via `build`. It never owns business logic.
///
/// This is the user interface for a section header used across the showcase
/// tabs — uppercase, bold, muted.
///
/// Requirements:
/// 1. [Section label] — profile-and-gallery-demos.gallery.browse-the-components-gallery
/// Renders an uppercase bold section header.
///
/// Relationships:
///
///       ┌──────────────────────┐
///       │ section label widget │
///       └──────────────────────┘
///      ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/common/showcase_tabs_shared/showcase_section_label_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

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
          color: AppBoxKitColors.muted,
        ),
      );
}
