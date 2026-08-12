/// A widget is a reusable UI piece composed by views. It receives data via
/// constructor params or [AppBoxKitStreamBuilder] bindings and renders its
/// slice of the surface — it holds no business logic and never decides when
/// an action runs.
///
/// This is the user interface for one folder row in the Folders list —
/// swipe-to-delete (confirmed), long-press-to-rename, tap to open.
///
/// Requirements:
/// 1. [Open folder] — browse-the-notes-in-a-folder
/// Tapping the row navigates into the folder's notes list.
///
/// Relationships:
///
///   ┌──────────────────────────────┐
///   │   notes folder row widget    │
///   └──────────────────────────────┘
///   ACT ▼
///   [1]
///   ┌──────────────────────────────┐
///   │       notes viewmodel        │
///   └──────────────────────────────┘
///      ════════ abxAction ════════
///
///  actions (ACT)
///    1. confirmDeleteFolder
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_notes_widgets/showcase_notes_folder_row_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_viewmodel.dart';

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
      // Rendered inline rather than via ShowcaseNotesRowWidget: that widget
      // is a thin adapter over AppBoxKitListTile, whose Material+InkWell
      // painted an ink splash over the native Liquid Glass tab chrome while
      // this row's long-press was still being recognized (ratified in
      // docs/plans/notes-shell-abxaction-adoption.md, decision 4 — the
      // InkWell and this GestureDetector's LongPressGestureRecognizer share
      // one gesture arena, so the InkWell's tap-down highlight painted before
      // the long press won it). The layout below matches AppBoxKitListTile's
      // tokens exactly so folder rows stay visually identical to the "All
      // Notes"/"Recently Deleted" rows in the same section.
      child: _ShowcaseNotesPressable(
        onTap: () => context.router.pushNamed('folder/${folder.id}'),
        onLongPress: onRename,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: abxSize48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: abxPad16,
              vertical: abxPad12,
            ),
            child: Row(
              children: [
                Icon(
                  AppBoxKitGlyphs.folder.icon,
                  size: abxSize20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: abxGap12),
                Expanded(
                  child: Text(folder.name, style: theme.textTheme.bodyLarge),
                ),
                Text(
                  '$count',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                Icon(
                  AppBoxKitGlyphs.chevronRight.icon,
                  size: abxSize18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Native-safe press indicator: dims [child] on press-down instead of
/// painting a Material ink splash — no [Material]/[InkWell]/[InkResponse]
/// ancestor, so it never leaks over a platform-view surface (Liquid Glass /
/// M3E). Local to this row; see the usage site for why.
class _ShowcaseNotesPressable extends StatefulWidget {
  const _ShowcaseNotesPressable({
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

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
          onLongPress: widget.onLongPress,
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
