import 'package:flutter/material.dart';
import 'package:appbox_kit_core/common/appbox_kit_app_constants.dart';
import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';
import 'package:appbox_kit_core/common/appbox_kit_ui_helpers.dart';

/// Inline error row — glyph + message in the error color, placed between the
/// fields and the primary CTA so a failed attempt is read in context.
///
/// **Shared (shell-wide):** previously the duplicated top-level
/// `Widget _errorRow(...)` in both `showcase_notes_auth` and
/// `showcase_notes_create_account`. Lives in the central
/// `showcase_notes_widgets` home.
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
