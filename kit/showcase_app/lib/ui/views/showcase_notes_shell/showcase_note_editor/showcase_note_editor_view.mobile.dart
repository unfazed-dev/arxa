/// A view composes adaptive primitives from the kit's native family and binds
/// the viewmodel's streams with [ArxaKitStreamBuilder], calling the viewmodel's
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
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_view.mobile.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';

import 'package:arxa_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart';

class ShowcaseNoteEditorViewMobile
    extends ViewModelWidget<ShowcaseNoteEditorViewModel> {
  const ShowcaseNoteEditorViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNoteEditorViewModel viewModel) {
    final theme = Theme.of(context);

    // One scaffold shell shared by the loading state and the loaded note, so
    // the back button never drops out while note$'s first event is pending.
    // glass-law-exempt: pushed route keeps its boxed bar; the body's native
    // glass rides a SingleChildScrollView, whose single child is clipped —
    // never sliver-culled — so rule 4's cull-seam shimmer cannot fire here.
    Scaffold shell(
            {String? title, List<Widget>? actions, required Widget body}) =>
        Scaffold(
          appBar: ArxaKitNativeAppBar(
            leading: ArxaKitNativeIconButton(
              glyph: ArxaKitGlyphs.back,
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
    return ArxaKitStreamBuilder<ShowcaseNoteModel?>(
      stream: viewModel.note$,
      loadingBuilder: (context) =>
          shell(body: const Center(child: ArxaKitNativeLoadingIndicator())),
      builder: (context, note) => shell(
        title: note == null
            ? null
            : viewModel.editedLabel(context, note.updatedAt),
        actions: note == null
            ? null
            : [
                ArxaKitNativeIconButton(
                  glyph:
                      note.pinned ? ArxaKitGlyphs.pin : ArxaKitGlyphs.unpin,
                  color: note.pinned ? theme.colorScheme.primary : null,
                  onPressed: viewModel.togglePin,
                ),
                ArxaKitNativeIconButton(
                  glyph: ArxaKitGlyphs.delete,
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
                  ? const Center(child: ArxaKitNativeLoadingIndicator())
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
