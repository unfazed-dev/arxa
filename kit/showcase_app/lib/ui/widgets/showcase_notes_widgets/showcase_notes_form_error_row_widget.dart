/// A widget is a reusable UI piece composed by views. It receives data via
/// constructor params or [AppBoxKitStreamBuilder] bindings and renders its
/// slice of the surface — it holds no business logic and never decides when
/// an action runs.
///
/// This is the user interface for an inline form error — glyph + message in the
/// error color, placed between the fields and the primary CTA.
///
/// Requirements:
/// 1. [Inline error display]
/// Shows a glyph + message in the error color so a failed attempt is read in
/// context.
///
/// Relationships:
///
/// Standalone — no viewmodel binding.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_notes_widgets/showcase_notes_form_error_row_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_showcase_app/ui/common/appbox_kit_app_constants.dart';
import 'package:appbox_kit_showcase_app/ui/common/appbox_kit_glyphs.dart';
import 'package:appbox_kit_showcase_app/ui/common/appbox_kit_ui_helpers.dart';

class ShowcaseNotesFormErrorRowWidget extends StatelessWidget {
  const ShowcaseNotesFormErrorRowWidget({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: abxSize12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppBoxKitGlyphs.error.icon,
              size: abxSize18, color: theme.colorScheme.error),
          appBoxKitHorizontalSpaceSmall,
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
