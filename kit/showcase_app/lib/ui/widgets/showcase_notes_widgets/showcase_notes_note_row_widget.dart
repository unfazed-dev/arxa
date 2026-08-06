import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_viewmodel.dart';

/// One note row: swipe actions differ by scope (trash vs. live folder), tap
/// always opens the editor. `confirmDismiss` always returns false — the
/// stream rebuild moves/removes the row once the mutation lands.
class ShowcaseNotesNoteRowWidget extends StatelessWidget {
  const ShowcaseNotesNoteRowWidget({
    super.key,
    required this.note,
    required this.viewModel,
    required this.onDeletePermanently,
    required this.formatDate,
  });

  final ShowcaseNoteModel note;
  final ShowcaseNotesFolderViewModel viewModel;

  /// Trash-scope end-to-start swipe handler — the view owns the
  /// permanent-delete confirmation dialog plumbing.
  final Future<void> Function() onDeletePermanently;

  /// Relative-date label formatter — the view owns the formatting helper.
  final String Function(DateTime updatedAt) formatDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTrash = viewModel.isTrash;

    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.horizontal,
      background: Container(
        color: isTrash ? theme.colorScheme.tertiary : theme.colorScheme.primary,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: kSize20),
        child: Icon(
          isTrash
              ? KitGlyphs.restore.icon
              : (note.pinned ? KitGlyphs.unpin.icon : KitGlyphs.pin.icon),
          color: isTrash
              ? theme.colorScheme.onTertiary
              : theme.colorScheme.onPrimary,
        ),
      ),
      secondaryBackground: Container(
        color: theme.colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: kSize20),
        child: Icon(KitGlyphs.delete.icon, color: theme.colorScheme.onError),
      ),
      confirmDismiss: (direction) async {
        if (isTrash) {
          if (direction == DismissDirection.endToStart) {
            await onDeletePermanently();
          } else {
            await viewModel.restore(note);
          }
        } else {
          if (direction == DismissDirection.endToStart) {
            await viewModel.moveToTrash(note);
          } else {
            await viewModel.togglePin(note);
          }
        }
        return false;
      },
      child: InkWell(
        onTap: () => context.router.pushNamed('note/${note.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: kSize16, vertical: kSize12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (note.pinned) ...[
                    horizontalSpaceTiny,
                    Icon(KitGlyphs.pin.icon,
                        size: kSize14, color: theme.colorScheme.primary),
                  ],
                ],
              ),
              verticalSpaceTiny,
              Text(
                '${formatDate(note.updatedAt)}  ${note.snippet}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
