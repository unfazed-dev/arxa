import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_viewmodel.dart';

/// The notes-list screen for one scope — 'all', 'trash', or a folder id (see
/// [ShowcaseNotesFolderViewModel.folderKey]). iOS Notes look: back + large title,
/// search (hidden in trash), grouped sections with swipe actions, compose FAB.
class ShowcaseNotesFolderView
    extends StackedView<ShowcaseNotesFolderViewModel> {
  const ShowcaseNotesFolderView({super.key});

  /// Streams-only house convention: the view never rebuilds off
  /// `notifyListeners` (the viewmodel never calls it) — every live value is
  /// bound with [KitStreamBuilder] at the subtree that needs it.
  @override
  bool get reactive => false;

  @override
  ShowcaseNotesFolderViewModel viewModelBuilder(BuildContext context) =>
      ShowcaseNotesFolderViewModel(
        folderKey: context.routeData.pathParams.getString('id'),
      );

  @override
  Widget builder(
    BuildContext context,
    ShowcaseNotesFolderViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseNotesFolderViewMobile(),
      tablet: (_) => const ShowcaseNotesFolderViewTablet(),
      desktop: (_) => const ShowcaseNotesFolderViewDesktop(),
    );
  }
}
