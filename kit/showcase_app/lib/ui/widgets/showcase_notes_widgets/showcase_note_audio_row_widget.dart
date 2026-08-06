import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
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
  final ShowcaseNoteAttachmentModel attachment;

  /// Long-press handler — the view owns the remove-confirmation dialog
  /// plumbing.
  final Future<void> Function(ShowcaseNoteAttachmentModel attachment) onRemoveAttachment;

  /// Duration label formatter — the view owns the formatting helper.
  final String Function(Duration duration) formatDuration;

  static Widget _progressBar(Duration progress, Duration? progressTotal) {
    if (progressTotal == null || progressTotal.inMilliseconds == 0) {
      return const SizedBox.shrink();
    }
    return AppBoxKitNativeProgress.linear(
      value: (progress.inMilliseconds / progressTotal.inMilliseconds)
          .clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = attachment.durationMs == null
        ? null
        : Duration(milliseconds: attachment.durationMs!);

    // Playing state is a stream now (the VM holds no relay fields) — the row
    // swaps play/pause and starts/stops its progress subscription off it.
    // Seeded false: the composed stream's first event lands a frame after
    // subscribe; the seed paints the play glyph for that first frame.
    return AppBoxKitStreamBuilder<bool>(
      stream: viewModel.isAttachmentPlaying$(attachment.id),
      initialData: false,
      builder: (context, playing) {
        return GestureDetector(
          onLongPress: () => onRemoveAttachment(attachment),
          child: AppBoxKitGlassCard(
            padding: const EdgeInsets.symmetric(
                horizontal: abxSize12, vertical: abxSize8),
            child: Row(
              children: [
                AppBoxKitNativeIconButton(
                  glyph: playing ? AppBoxKitGlyphs.pause : AppBoxKitGlyphs.play,
                  onPressed: () => viewModel.togglePlayback(attachment),
                ),
                appBoxKitHorizontalSpaceSmall,
                // Only the playing row subscribes to live progress, so position
                // ticks rebuild this bar alone — not the whole editor. Seeded so
                // the first frame paints at 0 without a loading flash.
                Expanded(
                  child: !playing
                      ? _progressBar(Duration.zero, total)
                      : AppBoxKitStreamBuilder<NotePlaybackProgress>(
                          stream: viewModel.playbackProgress$,
                          initialData: const (
                            position: Duration.zero,
                            duration: null
                          ),
                          builder: (context, prog) => _progressBar(
                              prog.position, prog.duration ?? total),
                        ),
                ),
                appBoxKitHorizontalSpaceSmall,
                Text(total == null ? '--:--' : formatDuration(total)),
              ],
            ),
          ),
        );
      },
    );
  }
}
