/// A widget is a reusable UI piece composed by views. It receives data via
/// constructor params or [AppBoxKitStreamBuilder] bindings and renders its
/// slice of the surface — it holds no business logic and never decides when
/// an action runs.
///
/// This is the user interface for an admin-section folder row — folder name,
/// owner subtitle, live count. Read-only by design.
///
/// Requirements:
/// 1. [Admin folder row]
/// Renders a read-only folder row with an owner subtitle for the admin
/// cross-owner section.
///
/// Relationships:
///
/// Standalone — no viewmodel binding.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_notes_widgets/showcase_notes_admin_folder_row_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_folder_model.dart';

/// Admin-section row: folder name + owner id subtitle + live count. Read-only
/// by design — folder detail streams are owner-scoped, so navigating into
/// another user's folder would show an empty list and read as a bug. The
/// section demonstrates role-gated *visibility*, nothing more.
class ShowcaseNotesAdminFolderRowWidget extends StatelessWidget {
  const ShowcaseNotesAdminFolderRowWidget({
    super.key,
    required this.folder,
    required this.count,
  });

  final ShowcaseNoteFolderModel folder;
  final int count;

  @override
  Widget build(BuildContext context) => AppBoxKitListTile(
        glyph: AppBoxKitGlyphs.folder,
        title: folder.name,
        subtitle: folder.owner,
        trailingValue: '$count',
      );
}
