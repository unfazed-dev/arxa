/// A widget is a reusable UI piece composed by views. It receives data via
/// constructor params or [AppBoxKitStreamBuilder] bindings and renders its
/// slice of the surface — it holds no business logic and never decides when
/// an action runs.
///
/// This is the user interface for the in-progress voice-recording row — cancel,
/// elapsed pill, and stop.
///
/// Requirements:
/// 1. [Recording controls] — attach-an-audio-recording-to-a-note
/// The cancel button discards the in-progress recording; the stop button stops
/// and attaches it.
///
/// Relationships:
///
///   ┌──────────────────────────────┐
///   │  note recording row widget   │
///   └──────────────────────────────┘
///   ACT ▼
///   [1-2]
///   ┌──────────────────────────────┐
///   │    note editor viewmodel     │
///   └──────────────────────────────┘
///      ════════ abxAction ════════
///
///  actions (ACT)
///    1. cancelRecording
///    2. stopRecording
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_notes_widgets/showcase_note_recording_row_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/common/ui_helpers.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart';

/// The in-progress voice-recording row: cancel, elapsed pill, stop.
class ShowcaseNoteRecordingRowWidget extends StatelessWidget {
  const ShowcaseNoteRecordingRowWidget({
    super.key,
    required this.viewModel,
    required this.elapsed,
  });
  final ShowcaseNoteEditorViewModel viewModel;

  /// Live elapsed time — arrives as a builder param from the toolbar's
  /// [AppBoxKitStreamBuilder] binding, never re-read off the viewmodel here.
  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        AppBoxKitNativeIconButton(
          glyph: AppBoxKitGlyphs.close,
          color: theme.colorScheme.onSurfaceVariant,
          onPressed: viewModel.cancelRecording,
        ),
        appBoxKitHorizontalSpaceSmall,
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: abxSize12, vertical: abxSize8),
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(abxRad20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.fiber_manual_record,
                    color: theme.colorScheme.error, size: 12),
                appBoxKitHorizontalSpaceXSmall,
                Text(
                  showcaseFormatDuration(elapsed),
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        appBoxKitHorizontalSpaceSmall,
        AppBoxKitNativeIconButton(
          glyph: AppBoxKitGlyphs.stop,
          color: theme.colorScheme.error,
          onPressed: viewModel.stopRecording,
        ),
      ],
    );
  }
}
