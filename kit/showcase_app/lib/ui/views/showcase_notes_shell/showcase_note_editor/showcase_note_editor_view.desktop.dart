/// A view composes adaptive primitives from the kit's native family and binds
/// the viewmodel's streams with [AppBoxKitStreamBuilder], calling the viewmodel's
/// actions on user input. It never contains business logic — every decision
/// lives in the viewmodel, and only the subtree bound to a changed stream
/// redraws.
///
/// This is the user interface for writing a note. The app bar shows the
/// last-edited label, pin, and delete actions; the body holds the text editor,
/// photo strip, and audio rows; the bottom toolbar carries camera, photo, and
/// mic actions — swapped for a recording row while voice capture is in progress.
///
/// Requirements:
/// 1. [Text editing] — edit-a-note
/// The text field calls onBodyChanged on every keystroke; the VM autosaves.
/// 2. [Pinning] — pin-a-note-to-the-top-of-the-inbox / unpin-a-pinned-note
/// The app-bar pin button toggles the pin.
/// 3. [Move to trash] — trash-a-note
/// The app-bar delete button moves the note to Recently Deleted.
/// 4. [Attaching photos] — attach-a-photo-to-a-note
/// The toolbar camera/photo buttons add a photo.
/// 5. [Removing attachments] — attach-a-photo-to-a-note
/// Long-press on a photo or audio row removes the attachment.
/// 6. [Recording voice notes] — attach-an-audio-recording-to-a-note
/// The toolbar mic button starts recording; stop attaches the voice note.
/// 7. [Discarding a recording] — attach-an-audio-recording-to-a-note
/// The recording row's cancel button throws away the in-progress recording.
/// 8. [Playing audio] — play-back-an-audio-attachment
/// The audio row play/pause button toggles playback with live progress.
/// 9. [Quick action] — attach-a-photo-to-a-note / attach-an-audio-recording-to-a-note
/// The route's quick action starts the camera or mic once the note loads.
/// 10. [Edited label] — edit-a-note
/// The app bar shows when the note was last edited.
///
/// Relationships:
///
///   ┌──────────────────────────────┐
///   │       note editor view       │
///   └──────────────────────────────┘
///   ACT ▼                    ▲ STRM
///   [1-10]                   [1-6]
///   ┌──────────────────────────────┐
///   │    note editor viewmodel     │
///   └──────────────────────────────┘
///      ════════ abxAction ════════
///
///  streams (STRM)              actions (ACT)
///    1. note$                    1. onBodyChanged
///    2. recordingElapsed$        2. togglePin
///    3. playingAttachmentId$     3. delete
///    4. playerState$             4. addPhoto
///    5. isAttachmentPlaying$     5. startRecording
///    6. playbackProgress$        6. stopRecording
///                                7. cancelRecording
///                                8. togglePlayback
///                                9. confirmRemoveAttachment
///                               10. resolvePath
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_view.desktop.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart';

class ShowcaseNoteEditorViewDesktop
    extends ViewModelWidget<ShowcaseNoteEditorViewModel> {
  const ShowcaseNoteEditorViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNoteEditorViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, DESKTOP UI - ShowcaseNoteEditorView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
