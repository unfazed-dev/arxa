import 'package:flutter/material.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:ui_library/ui_library.dart';
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
        child: KitMotionScope(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: kSize16, vertical: kSize8),
            child: viewModel.isRecording
                ? ShowcaseNoteRecordingRowWidget(
                    viewModel: viewModel, formatDuration: formatDuration)
                : Row(
                    children: [
                      if (viewModel.isCameraAvailable) ...[
                        KitNativeIconButton(
                          glyph: KitGlyphs.camera,
                          onPressed: () => viewModel.addPhoto(fromCamera: true),
                        ),
                        horizontalSpaceSmall,
                      ],
                      KitNativeIconButton(
                        glyph: KitGlyphs.photo,
                        onPressed: () => viewModel.addPhoto(fromCamera: false),
                      ),
                      const Spacer(),
                      KitNativeIconButton(
                        glyph: KitGlyphs.mic,
                        onPressed: () async {
                          final started = await viewModel.startRecording();
                          if (!started && context.mounted) {
                            locator<KitNotificationService>().show(
                              'Microphone permission needed',
                              kind: KitNotificationKind.warning,
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
      );
}
