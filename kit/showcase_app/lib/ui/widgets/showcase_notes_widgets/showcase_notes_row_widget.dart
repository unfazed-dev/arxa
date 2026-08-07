/// A widget is a reusable UI piece composed by views. It receives data via
/// constructor params or [AppBoxKitStreamBuilder] bindings and renders its
/// slice of the surface — it holds no business logic and never decides when
/// an action runs.
///
/// This is the user interface for a single tappable folder-list row — glyph,
/// label, trailing count, chevron. A thin adapter over [AppBoxKitListTile].
///
/// Requirements:
/// 1. [Folder-list row]
/// Renders a glyph, label, trailing count, and chevron in the kit's grouped-list
/// row idiom.
///
/// Relationships:
///
/// Standalone — no viewmodel binding.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_notes_widgets/showcase_notes_row_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

class ShowcaseNotesRowWidget extends StatelessWidget {
  const ShowcaseNotesRowWidget({
    super.key,
    required this.glyph,
    required this.label,
    required this.trailingCount,
    required this.onTap,
  });

  final AppBoxKitGlyph glyph;
  final String label;
  final int trailingCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppBoxKitListTile(
        glyph: glyph,
        title: label,
        trailingValue: '$trailingCount',
        showChevron: true,
        onTap: onTap,
      );
}
