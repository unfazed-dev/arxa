/// A view composes adaptive primitives from the kit's native family and binds
/// the viewmodel's streams with [AppBoxKitStreamBuilder], calling the viewmodel's
/// actions on user input. It never contains business logic — every decision
/// lives in the viewmodel, and only the subtree bound to a changed stream
/// redraws.
///
/// This is the user interface for the notes list inside one scope — All Notes,
/// a specific folder, or Recently Deleted. The list shows grouped sections with
/// swipe actions (pin/unpin, trash/restore, permanent delete), a pinned search
/// bar (hidden in trash), and a compose FAB.
///
/// Requirements:
/// 1. [Browse notes] — browse-the-notes-in-a-folder
/// The list shows notes grouped by date section, with a back button and title.
/// 2. [Create a note] — create-a-note
/// The compose FAB creates a note and navigates to the editor.
/// 3. [Pin a note] — pin-a-note-to-the-top-of-the-inbox
/// Swipe right-to-left on a live note toggles its pin.
/// 4. [Unpin a note] — unpin-a-pinned-note
/// Swipe right-to-left on a pinned note unpins it.
/// 5. [Trash a note] — trash-a-note
/// Swipe left-to-right on a live note moves it to Recently Deleted.
/// 6. [Restore a note] — restore-a-trashed-note
/// In trash scope, swipe left-to-right restores the note.
/// 7. [Delete permanently] — delete-a-note-forever
/// In trash scope, swipe left-to-right permanently deletes; the bar action
/// empties all.
/// 8. [Search notes] — search-notes-by-text
/// The pinned search bar filters the list by text.
///
/// Relationships:
///
///   ┌──────────────────────────────┐
///   │      notes folder view       │
///   └──────────────────────────────┘
///   ACT ▼                    ▲ STRM
///   [1-7]                    [1-2]
///   ┌──────────────────────────────┐
///   │    notes folder viewmodel    │
///   └──────────────────────────────┘
///      ════════ abxAction ════════
///
///  streams (STRM)              actions (ACT)
///    1. title$                   1. togglePin
///    2. groups$                  2. moveToTrash
///                                3. restore
///                                4. confirmDeletePermanently
///                                5. confirmEmptyTrash
///                                6. compose
///                                7. setQuery
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_view.desktop.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_viewmodel.dart';

class ShowcaseNotesFolderViewDesktop
    extends ViewModelWidget<ShowcaseNotesFolderViewModel> {
  const ShowcaseNotesFolderViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNotesFolderViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, DESKTOP UI - ShowcaseNotesFolderView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
