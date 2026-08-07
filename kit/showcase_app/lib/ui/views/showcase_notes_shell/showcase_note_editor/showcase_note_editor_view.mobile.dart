import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart';

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
          appBar: AppBoxKitNativeAppBar(
            leading: AppBoxKitNativeIconButton(
              glyph: AppBoxKitGlyphs.back,
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
    return AppBoxKitStreamBuilder<ShowcaseNoteModel?>(
      stream: viewModel.note$,
      loadingBuilder: (context) =>
          shell(body: const Center(child: AppBoxKitNativeLoadingIndicator())),
      builder: (context, note) => shell(
        title: note == null ? null : viewModel.editedLabel(context, note.updatedAt),
        actions: note == null
            ? null
            : [
                AppBoxKitNativeIconButton(
                  glyph: note.pinned ? AppBoxKitGlyphs.pin : AppBoxKitGlyphs.unpin,
                  color: note.pinned ? theme.colorScheme.primary : null,
                  onPressed: viewModel.togglePin,
                ),
                AppBoxKitNativeIconButton(
                  glyph: AppBoxKitGlyphs.delete,
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
                  ? const Center(child: AppBoxKitNativeLoadingIndicator())
                  : ShowcaseNoteEditorBodyWidget(
                      viewModel: viewModel,
                      note: note,
                    ),
            ),
            ShowcaseNoteEditorBottomToolbarWidget(viewModel: viewModel),
          ],
        ),
      ),
    );
  }
}
