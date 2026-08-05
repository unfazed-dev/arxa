import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/models/showcase_note_folder.dart';

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

  final ShowcaseNoteFolder folder;
  final int count;

  @override
  Widget build(BuildContext context) => KitListTile(
        glyph: KitGlyphs.folder,
        title: folder.name,
        subtitle: folder.owner,
        trailingValue: '$count',
      );
}
