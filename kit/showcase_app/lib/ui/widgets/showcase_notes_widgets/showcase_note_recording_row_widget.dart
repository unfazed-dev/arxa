import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart';

/// The in-progress voice-recording row: cancel, elapsed pill, stop.
class ShowcaseNoteRecordingRowWidget extends StatelessWidget {
  const ShowcaseNoteRecordingRowWidget({
    super.key,
    required this.viewModel,
    required this.formatDuration,
  });
  final ShowcaseNoteEditorViewModel viewModel;

  /// Duration label formatter — the view owns the formatting helper.
  final String Function(Duration duration) formatDuration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final elapsed = viewModel.recordingElapsed ?? Duration.zero;
    return Row(
      children: [
        KitNativeIconButton(
          glyph: KitGlyphs.close,
          color: theme.colorScheme.onSurfaceVariant,
          onPressed: viewModel.cancelRecording,
        ),
        horizontalSpaceSmall,
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: kSize12, vertical: kSize8),
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(kRad20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.fiber_manual_record,
                    color: theme.colorScheme.error, size: 12),
                horizontalSpaceXSmall,
                Text(
                  formatDuration(elapsed),
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        horizontalSpaceSmall,
        KitNativeIconButton(
          glyph: KitGlyphs.stop,
          color: theme.colorScheme.error,
          onPressed: viewModel.stopRecording,
        ),
      ],
    );
  }
}
