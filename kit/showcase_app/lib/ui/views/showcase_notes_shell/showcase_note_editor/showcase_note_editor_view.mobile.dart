import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:ui_library/ui_library.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:appbox_kit_showcase_app/app/app.dialogs.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart';

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
    final theme = Theme.of(context);

    // One scaffold shell shared by the loading state and the loaded note, so
    // the back button never drops out while note$'s first event is pending.
    Scaffold shell({String? title, List<Widget>? actions, required Widget body}) =>
        Scaffold(
          appBar: KitNativeAppBar(
            leading: KitNativeIconButton(
              glyph: KitGlyphs.back,
              onPressed: () => context.popRoute(),
            ),
            title: title,
            actions: actions,
            automaticallyImplyLeading: false,
          ),
          body: SafeArea(child: body),
        );

    // Streams-only: note$ feeds the app bar (edited label, pin/delete) and the
    // body swap. Media chrome binds its own streams inside the widgets.
    return KitStreamBuilder<ShowcaseNoteModel?>(
      stream: viewModel.note$,
      loadingBuilder: (context) =>
          shell(body: const Center(child: KitNativeLoadingIndicator())),
      builder: (context, note) => shell(
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
        body: Column(
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
  ShowcaseNoteAttachmentModel attachment,
) async {
  final res = await locator<DialogService>().showCustomDialog(
    variant: DialogType.showcaseConfirm,
    title: 'Remove attachment?',
    data: (actionLabel: 'Remove', destructive: false),
  );
  if (res?.confirmed == true) {
    await viewModel.removeAttachment(attachment);
  }
}
