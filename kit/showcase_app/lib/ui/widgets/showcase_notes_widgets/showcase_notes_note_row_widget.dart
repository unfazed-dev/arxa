/// A widget is a reusable UI piece composed by views. It receives data via
/// constructor params or [AppBoxKitStreamBuilder] bindings and renders its
/// slice of the surface — it holds no business logic and never decides when
/// an action runs.
///
/// This is the user interface for one note row in the notes list — swipe actions
/// differ by scope (trash vs. live), tap always opens the editor.
///
/// Requirements:
/// 1. [Pin] — pin-a-note-to-the-top-of-the-inbox
/// Swipe right-to-left on a live note toggles its pin.
/// 2. [Unpin] — unpin-a-pinned-note
/// Swipe right-to-left on a pinned note unpins it.
/// 3. [Trash] — trash-a-note
/// Swipe left-to-right on a live note moves it to Recently Deleted.
/// 4. [Restore] — restore-a-trashed-note
/// In trash scope, swipe left-to-right restores the note.
/// 5. [Delete permanently] — delete-a-note-forever
/// In trash scope, swipe left-to-right permanently deletes the note.
///
/// Relationships:
///
///   ┌──────────────────────────────┐
///   │    notes note row widget     │
///   └──────────────────────────────┘
///   ACT ▼
///   [1-3]
///   ┌──────────────────────────────┐
///   │    notes folder viewmodel    │
///   └──────────────────────────────┘
///      ════════ abxAction ════════
///
///  actions (ACT)
///    1. togglePin
///    2. moveToTrash
///    3. restore
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_notes_widgets/showcase_notes_note_row_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_viewmodel.dart';

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
        padding: const EdgeInsets.symmetric(horizontal: abxSize20),
        child: Icon(
          isTrash
              ? AppBoxKitGlyphs.restore.icon
              : (note.pinned ? AppBoxKitGlyphs.unpin.icon : AppBoxKitGlyphs.pin.icon),
          color: isTrash
              ? theme.colorScheme.onTertiary
              : theme.colorScheme.onPrimary,
        ),
      ),
      secondaryBackground: Container(
        color: theme.colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: abxSize20),
        child: Icon(AppBoxKitGlyphs.delete.icon, color: theme.colorScheme.onError),
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
      // No InkWell/Material splash here (ratified in
      // docs/plans/notes-shell-abxaction-adoption.md, decision 4): its ink
      // painted over the native Liquid Glass tab chrome on long-press-style
      // holds. No shared kit-level press-state primitive exists yet (checked
      // kit/ui_library/lib/utils/kit_action and every kit widget), so this
      // row owns a minimal local one.
      child: _ShowcaseNotesPressable(
        onTap: () => context.router.pushNamed('note/${note.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: abxSize16, vertical: abxSize12),
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
                    appBoxKitHorizontalSpaceTiny,
                    Icon(AppBoxKitGlyphs.pin.icon,
                        size: abxSize14, color: theme.colorScheme.primary),
                  ],
                ],
              ),
              appBoxKitVerticalSpaceTiny,
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

/// Dims [child] on press-down instead of painting ink over native surfaces.
class _ShowcaseNotesPressable extends StatefulWidget {
  const _ShowcaseNotesPressable({
    required this.child,
    this.onTap,
  });

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_ShowcaseNotesPressable> createState() =>
      _ShowcaseNotesPressableState();
}

class _ShowcaseNotesPressableState extends State<_ShowcaseNotesPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: AnimatedOpacity(
            opacity: _pressed ? 0.6 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: widget.child,
          ),
        ),
      );
}
