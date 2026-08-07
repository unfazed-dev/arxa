import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_viewmodel.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';

/// A folder row: swipe-to-delete (confirmed), long-press-to-rename, tap to
/// open. `confirmDismiss` always returns false — the section rebuilds off
/// [ShowcaseNotesViewModel.overview$] once the mutation lands, so the
/// Dismissible never needs to remove the row itself.
class ShowcaseNotesFolderRowWidget extends StatelessWidget {
  const ShowcaseNotesFolderRowWidget({
    super.key,
    required this.folder,
    required this.count,
    required this.viewModel,
    required this.onRename,
  });

  final ShowcaseNoteFolderModel folder;
  final int count;
  final ShowcaseNotesViewModel viewModel;

  /// Long-press handler — the view wires this to the viewmodel's
  /// `renameFolderWithPrompt` (G8: the VM owns the dialog).
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey(folder.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: abxSize20),
        child: Icon(AppBoxKitGlyphs.delete.icon, color: theme.colorScheme.onError),
      ),
      confirmDismiss: (_) async {
        await viewModel.confirmDeleteFolder(folder);
        return false;
      },
      child: GestureDetector(
        onLongPress: onRename,
        child: ShowcaseNotesRowWidget(
          glyph: AppBoxKitGlyphs.folder,
          label: folder.name,
          trailingCount: count,
          onTap: () => context.router.pushNamed('folder/${folder.id}'),
        ),
      ),
    );
  }
}
