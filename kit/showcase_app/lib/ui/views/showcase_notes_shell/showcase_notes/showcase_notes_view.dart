import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_viewmodel.dart';

/// The "Folders" screen — Notes tab root. Signed-out state embeds
/// [NotesAuthPanel] directly (seamless, no navigation); signed-in state is
/// grouped rounded sections mirroring iOS Notes' Folders list
/// (All Notes / user folders / Recently Deleted).
class ShowcaseNotesView extends StackedView<ShowcaseNotesViewModel> {
  const ShowcaseNotesView({super.key});

  /// Streams-only house convention: the view never rebuilds off
  /// `notifyListeners` (the viewmodel never calls it) — every live value is
  /// bound with [KitStreamBuilder] at the subtree that needs it.
  @override
  bool get reactive => false;

  @override
  ShowcaseNotesViewModel viewModelBuilder(BuildContext context) =>
      ShowcaseNotesViewModel();

  @override
  Widget builder(
    BuildContext context,
    ShowcaseNotesViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseNotesViewMobile(),
      tablet: (_) => const ShowcaseNotesViewTablet(),
      desktop: (_) => const ShowcaseNotesViewDesktop(),
    );
  }
}
