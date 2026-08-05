import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/notes/models/note_attachment.dart';
import 'package:appbox_kit_showcase_app/ui/common/showcase_notes_shared.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';

import 'showcase_note_editor_viewmodel.dart';

String _fmtDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

String _editedLabel(BuildContext context, DateTime updatedAt) {
  final local = updatedAt.toLocal();
  final now = DateTime.now();
  final sameDay = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (sameDay) {
    return 'Edited ${TimeOfDay.fromDateTime(local).format(context)}';
  }
  return 'Edited ${local.month}/${local.day}/${local.year}';
}

class ShowcaseNoteEditorViewMobile
    extends ViewModelWidget<ShowcaseNoteEditorViewModel> {
  const ShowcaseNoteEditorViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNoteEditorViewModel viewModel) {
    final note = viewModel.note;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: KitNativeAppBar(
        leading: KitNativeIconButton(
          glyph: KitGlyphs.back,
          onPressed: () => context.popRoute(),
        ),
        title: note == null ? null : _editedLabel(context, note.updatedAt),
        actions: note == null
            ? null
            : [
                KitNativeIconButton(
                  glyph: note.pinned ? KitGlyphs.pin : KitGlyphs.unpin,
                  color: note.pinned ? theme.colorScheme.primary : null,
                  onPressed: viewModel.togglePin,
                ),
                KitNativeIconButton(
                  glyph: KitGlyphs.delete,
                  color: theme.colorScheme.error,
                  onPressed: () async {
                    await viewModel.delete();
                    if (context.mounted) context.popRoute();
                  },
                ),
              ],
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: note == null
                  ? const Center(child: KitNativeLoadingIndicator())
                  : ShowcaseNoteEditorBodyWidget(
                      viewModel: viewModel,
                      note: note,
                      onRemoveAttachment: (attachment) =>
                          _confirmRemove(context, viewModel, attachment),
                      formatDuration: _fmtDuration,
                    ),
            ),
            ShowcaseNoteEditorBottomToolbarWidget(
              viewModel: viewModel,
              formatDuration: _fmtDuration,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmRemove(
  BuildContext context,
  ShowcaseNoteEditorViewModel viewModel,
  NoteAttachment attachment,
) async {
  if (await confirmDialog(context,
      title: 'Remove attachment?', actionLabel: 'Remove')) {
    await viewModel.removeAttachment(attachment);
  }
}
