import 'package:flutter/material.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';

/// The editor's bottom toolbar: camera/photo/mic actions, swapped for the
/// recording row while a voice note is capturing.
class ShowcaseNoteEditorBottomToolbarWidget extends StatelessWidget {
  const ShowcaseNoteEditorBottomToolbarWidget({
    super.key,
    required this.viewModel,
    required this.formatDuration,
  });
  final ShowcaseNoteEditorViewModel viewModel;

  /// Duration label formatter — the view owns the formatting helper.
  final String Function(Duration duration) formatDuration;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        // Scope lives on the toolbar itself: one settle on first mount. When
        // a recording session ends the Row re-mounts AFTER the scope timeline
        // has finished, so it renders settled — no entrance replay (the old
        // unkeyed flutter_animate chain replayed on every toggle-back).
        child: AppBoxKitMotionScope(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: axSize16, vertical: axSize8),
            // Streams-only: recordingElapsed$ (a seeded BehaviorSubject on the
            // media adapter, passed through the VM) swaps the action row for
            // the recording row and feeds the live elapsed pill.
            child: AppBoxKitStreamBuilder<Duration?>(
              stream: viewModel.recordingElapsed$,
              builder: (context, elapsed) => elapsed != null
                  ? ShowcaseNoteRecordingRowWidget(
                      viewModel: viewModel,
                      elapsed: elapsed,
                      formatDuration: formatDuration,
                    )
                  : Row(
                      children: [
                        if (viewModel.isCameraAvailable) ...[
                          AppBoxKitNativeIconButton(
                            glyph: AppBoxKitGlyphs.camera,
                            onPressed: () =>
                                viewModel.addPhoto(fromCamera: true),
                          ),
                          appBoxKitHorizontalSpaceSmall,
                        ],
                        AppBoxKitNativeIconButton(
                          glyph: AppBoxKitGlyphs.photo,
                          onPressed: () => viewModel.addPhoto(fromCamera: false),
                        ),
                        const Spacer(),
                        AppBoxKitNativeIconButton(
                          glyph: AppBoxKitGlyphs.mic,
                          onPressed: () async {
                            final started = await viewModel.startRecording();
                            if (!started && context.mounted) {
                              appBoxKitLocator<AppBoxKitNotificationService>().show(
                                'Microphone permission needed',
                                kind: AppBoxKitNotificationKind.warning,
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
