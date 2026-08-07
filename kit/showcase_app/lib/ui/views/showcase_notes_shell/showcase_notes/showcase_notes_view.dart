/// A view composes adaptive primitives from the kit's native family and binds
/// the viewmodel's streams with [AppBoxKitStreamBuilder], calling the viewmodel's
/// actions on user input. It never contains business logic — every decision
/// lives in the viewmodel, and only the subtree bound to a changed stream
/// redraws.
///
/// This is the user interface for the Folders list — the Notes tab root.
/// Signed out, it embeds the auth or create-account panel in place; signed in,
/// it shows grouped sections with All Notes, user folders, Recently Deleted,
/// and an admin-only cross-owner section. The app bar carries the new-folder
/// action and sign-out.
///
/// Requirements:
/// 1. [Browse folders] — browse-the-notes-in-a-folder
/// The signed-in screen lists folders with live note counts in grouped
/// sections; tapping a folder opens its notes list.
/// 2. [Create a folder] — create-a-folder
/// The app-bar action prompts for a name and creates the folder.
///
/// Relationships:
///
///   ┌──────────────────────────────┐
///   │          notes view          │
///   └──────────────────────────────┘
///   ACT ▼                    ▲ STRM
///   [1-6]                    [1-4]
///   ┌──────────────────────────────┐
///   │       notes viewmodel        │
///   └──────────────────────────────┘
///      ════════ abxAction ════════
///
///  streams (STRM)              actions (ACT)
///    1. session$                 1. createFolderWithPrompt
///    2. overview$                2. renameFolderWithPrompt
///    3. adminOverview$           3. confirmDeleteFolder
///    4. showCreateAccount$       4. signOut
///                                5. openCreateAccount
///                                6. closeCreateAccount
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

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
  /// bound with [AppBoxKitStreamBuilder] at the subtree that needs it.
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
