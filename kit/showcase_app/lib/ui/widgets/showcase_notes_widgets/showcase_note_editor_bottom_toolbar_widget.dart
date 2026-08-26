/// A widget is a reusable UI piece composed by views. It receives data via
/// constructor params or [ArxaKitStreamBuilder] bindings and renders its
/// slice of the surface — it holds no business logic and never decides when
/// an action runs.
///
/// This is the user interface for the editor's bottom toolbar — camera, photo,
/// and mic actions, swapped for the recording row while voice capture is in
/// progress.
///
/// Requirements:
/// 1. [Attach photo] — attach-a-photo-to-a-note
/// The camera and photo buttons add a photo to the note.
/// 2. [Record voice] — attach-an-audio-recording-to-a-note
/// The mic button starts recording; the recording row's stop button stops and
/// attaches; cancel discards.
///
/// Relationships:
///
///   ┌──────────────────────────────────┐
///   │note editor bottom toolbar widget │
///   └──────────────────────────────────┘
///   ACT ▼                        ▲ STRM
///   [1-4]
///   ┌──────────────────────────────────┐
///   │      note editor viewmodel       │
///   └──────────────────────────────────┘
///        ════════ abxAction ════════
///
///  streams (STRM)              actions (ACT)
///    1. recordingElapsed$        1. addPhoto
///                                2. startRecording
///                                3. stopRecording
///                                4. cancelRecording
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_notes_widgets/showcase_note_editor_bottom_toolbar_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_motion/arxa_kit_motion.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';

class ShowcaseNoteEditorBottomToolbarWidget extends StatelessWidget {
  const ShowcaseNoteEditorBottomToolbarWidget({
    super.key,
    required this.viewModel,
  });
  final ShowcaseNoteEditorViewModel viewModel;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        // Scope lives on the toolbar itself: one settle on first mount. When
        // a recording session ends the Row re-mounts AFTER the scope timeline
        // has finished, so it renders settled — no entrance replay (the old
        // unkeyed flutter_animate chain replayed on every toggle-back).
        child: ArxaKitMotionScope(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: abxSize16, vertical: abxSize8),
            // Streams-only: recordingElapsed$ (a seeded BehaviorSubject on the
            // media adapter, passed through the VM) swaps the action row for
            // the recording row and feeds the live elapsed pill.
            child: ArxaKitStreamBuilder<Duration?>(
              stream: viewModel.recordingElapsed$,
              builder: (context, elapsed) => elapsed != null
                  ? ShowcaseNoteRecordingRowWidget(
                      viewModel: viewModel,
                      elapsed: elapsed,
                    )
                  : Row(
                      children: [
                        if (viewModel.isCameraAvailable) ...[
                          ArxaKitNativeIconButton(
                            glyph: ArxaKitGlyphs.camera,
                            onPressed: () =>
                                viewModel.addPhoto(fromCamera: true),
                          ),
                          arxaKitHorizontalSpaceSmall,
                        ],
                        ArxaKitNativeIconButton(
                          glyph: ArxaKitGlyphs.photo,
                          onPressed: () =>
                              viewModel.addPhoto(fromCamera: false),
                        ),
                        const Spacer(),
                        ArxaKitNativeIconButton(
                          glyph: ArxaKitGlyphs.mic,
                          onPressed: () async {
                            final started = await viewModel.startRecording();
                            if (!started && context.mounted) {
                              arxaKitLocator<ArxaKitNotificationService>()
                                  .show(
                                'Microphone permission needed',
                                kind: ArxaKitNotificationKind.warning,
                                context: context,
                              );
                            }
                          },
                        ),
                      ],
                    )
                      // The toolbar settles in after the surface mounts — one
                      // rise, not a stagger (the editor is a destination, not
                      // a list).
                      .wake(order: 0),
            ),
          ),
        ),
      );
}
