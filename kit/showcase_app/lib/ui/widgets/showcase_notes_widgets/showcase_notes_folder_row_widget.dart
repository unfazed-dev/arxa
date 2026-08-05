import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/models/showcase_notes_models/showcase_note_folder_model.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:appbox_kit_showcase_app/app/app.dialogs.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_viewmodel.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';

/// A folder row: swipe-to-delete (confirmed), long-press-to-rename, tap to
/// open. `confirmDismiss` always returns false — the section rebuilds off
/// [ShowcaseNotesViewModel.overview]'s stream once the mutation lands, so the
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

  /// Long-press handler — the view owns the rename dialog plumbing
  /// (DialogType.showcaseTextInput + `renameFolder`).
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
        padding: const EdgeInsets.symmetric(horizontal: kSize20),
        child: Icon(KitGlyphs.delete.icon, color: theme.colorScheme.onError),
      ),
      confirmDismiss: (_) async {
        final res = await locator<DialogService>().showCustomDialog(
          variant: DialogType.showcaseConfirm,
          title: 'Delete Folder',
          description:
              'Notes in "${folder.name}" will move to Recently Deleted.',
          data: (actionLabel: 'Delete', destructive: true),
        );
        if (res?.confirmed == true) {
          await viewModel.deleteFolder(folder);
        }
        return false;
      },
      child: GestureDetector(
        onLongPress: onRename,
        child: ShowcaseNotesRowWidget(
          glyph: KitGlyphs.folder,
          label: folder.name,
          trailingCount: count,
          onTap: () => context.router.pushNamed('folder/${folder.id}'),
        ),
      ),
    );
  }
}
