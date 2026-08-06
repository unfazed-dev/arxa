import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart';

/// The note editor. Route `/notes/note/:id`.
class ShowcaseNoteEditorView extends StackedView<ShowcaseNoteEditorViewModel> {
  const ShowcaseNoteEditorView({super.key});

  /// Streams-only house convention: the view never rebuilds off
  /// `notifyListeners` (the viewmodel never calls it) — every live value is
  /// bound with [AppBoxKitStreamBuilder] at the subtree that needs it.
  @override
  bool get reactive => false;

  @override
  Widget builder(
    BuildContext context,
    ShowcaseNoteEditorViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseNoteEditorViewMobile(),
      tablet: (_) => const ShowcaseNoteEditorViewTablet(),
      desktop: (_) => const ShowcaseNoteEditorViewDesktop(),
    );
  }

  @override
  ShowcaseNoteEditorViewModel viewModelBuilder(BuildContext context) =>
      ShowcaseNoteEditorViewModel(
          noteId: context.routeData.pathParams.getString('id'));
}
