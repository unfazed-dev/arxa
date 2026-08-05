import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/models/showcase_note_attachment.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart';

/// One audio attachment row: play/pause, live progress bar, duration label.
class ShowcaseNoteAudioRowWidget extends StatelessWidget {
  const ShowcaseNoteAudioRowWidget({
    super.key,
    required this.viewModel,
    required this.attachment,
    required this.onRemoveAttachment,
    required this.formatDuration,
  });
  final ShowcaseNoteEditorViewModel viewModel;
  final ShowcaseNoteAttachment attachment;

  /// Long-press handler — the view owns the remove-confirmation dialog
  /// plumbing.
  final Future<void> Function(ShowcaseNoteAttachment attachment) onRemoveAttachment;

  /// Duration label formatter — the view owns the formatting helper.
  final String Function(Duration duration) formatDuration;

  static Widget _progressBar(Duration progress, Duration? progressTotal) {
    if (progressTotal == null || progressTotal.inMilliseconds == 0) {
      return const SizedBox.shrink();
    }
    return KitNativeProgress.linear(
      value: (progress.inMilliseconds / progressTotal.inMilliseconds)
          .clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playing = viewModel.isAttachmentPlaying(attachment.id);
    final total = attachment.durationMs == null
        ? null
        : Duration(milliseconds: attachment.durationMs!);

    return GestureDetector(
      onLongPress: () => onRemoveAttachment(attachment),
      child: KitGlassCard(
        padding:
            const EdgeInsets.symmetric(horizontal: kSize12, vertical: kSize8),
        child: Row(
          children: [
            KitNativeIconButton(
              glyph: playing ? KitGlyphs.pause : KitGlyphs.play,
              onPressed: () => viewModel.togglePlayback(attachment),
            ),
            horizontalSpaceSmall,
            // Only the playing row subscribes to live progress, so position
            // ticks rebuild this bar alone — not the whole editor. Seeded so
            // the first frame paints at 0 without a loading flash.
            Expanded(
              child: !playing
                  ? _progressBar(Duration.zero, total)
                  : KitStreamBuilder<NotePlaybackProgress>(
                      stream: viewModel.playbackProgress$,
                      initialData: const (
                        position: Duration.zero,
                        duration: null
                      ),
                      builder: (context, prog) =>
                          _progressBar(prog.position, prog.duration ?? total),
                    ),
            ),
            horizontalSpaceSmall,
            Text(total == null ? '--:--' : formatDuration(total)),
          ],
        ),
      ),
    );
  }
}
