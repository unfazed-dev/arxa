/// A view composes adaptive primitives from the kit's native family and binds
/// the viewmodel's streams with [ArxaKitStreamBuilder], calling the viewmodel's
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
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_view.desktop.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

import 'package:arxa_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_viewmodel.dart';

class ShowcaseNotesViewDesktop extends ViewModelWidget<ShowcaseNotesViewModel> {
  const ShowcaseNotesViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNotesViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, DESKTOP UI - ShowcaseNotesView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
