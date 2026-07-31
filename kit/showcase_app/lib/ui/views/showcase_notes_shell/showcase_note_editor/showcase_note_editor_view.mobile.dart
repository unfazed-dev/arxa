import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/notes/models/note.dart';
import 'package:appbox_kit_showcase_app/notes/models/note_attachment.dart';
import 'package:appbox_kit_showcase_app/ui/common/app_colors.dart';
import 'package:appbox_kit_showcase_app/ui/common/showcase_notes_shared.dart';

import 'showcase_note_editor_viewmodel.dart';

String _fmtDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

String _editedLabel(BuildContext context, DateTime updatedAt) {
  final local = updatedAt.toLocal();
  final now = DateTime.now();
  final sameDay = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (sameDay) {
    return 'Edited ${TimeOfDay.fromDateTime(local).format(context)}';
  }
  return 'Edited ${local.month}/${local.day}/${local.year}';
}

class ShowcaseNoteEditorViewMobile
    extends ViewModelWidget<ShowcaseNoteEditorViewModel> {
  const ShowcaseNoteEditorViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNoteEditorViewModel viewModel) {
    final note = viewModel.note;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: KitNativeAppBar(
        leading: KitNativeIconButton(
          glyph: KitGlyphs.back,
          onPressed: () => context.popRoute(),
        ),
        title: note == null ? null : _editedLabel(context, note.updatedAt),
        actions: note == null
            ? null
            : [
                KitNativeIconButton(
                  glyph: note.pinned ? KitGlyphs.pin : KitGlyphs.unpin,
                  color: note.pinned ? theme.colorScheme.primary : null,
                  onPressed: viewModel.togglePin,
                ),
                KitNativeIconButton(
                  glyph: KitGlyphs.delete,
                  color: theme.colorScheme.error,
                  onPressed: () async {
                    await viewModel.delete();
                    if (context.mounted) context.popRoute();
                  },
                ),
              ],
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: note == null
                  ? const Center(child: KitNativeLoadingIndicator())
                  : _EditorBody(viewModel: viewModel, note: note),
            ),
            _BottomToolbar(viewModel: viewModel),
          ],
        ),
      ),
    );
  }
}

/// Owns the body field's [TextEditingController] — the editor is a *document*
/// (borderless multiline), not a capsule form field, so the kit's
/// [KitFieldTextField] bridge (which wraps [KitNativeTextField]) is the wrong
/// widget here. This leaf applies the bridge's *rationale* instead: the view
/// owns the controller's lifecycle (create/seed/dispose for IME + cursor),
/// the value mirror stays in the viewmodel (`ShowcaseNoteEditorViewModel.body`)
/// and drives autosave. Not a "StatefulWidget form host" anti-pattern — there
/// is no form/field state split from the VM; the controller is view plumbing
/// for a document editor, the same way stacked's generated `$View` form mixin
/// is stateful purely for controller disposal.
class _EditorBody extends StatefulWidget {
  const _EditorBody({required this.viewModel, required this.note});
  final ShowcaseNoteEditorViewModel viewModel;
  final Note note;

  @override
  State<_EditorBody> createState() => _EditorBodyState();
}

class _EditorBodyState extends State<_EditorBody> {
  late final TextEditingController _bodyController;

  @override
  void initState() {
    super.initState();
    // Seed once from the VM's loaded body. The parent only mounts _EditorBody
    // once note != null, so viewModel.body is the loaded body here. The VM
    // never writes this controller again — typing flows OUT via onChanged, and
    // external note updates (attachments/pin) don't re-seed (VM's
    // _textInitialized guard), so user typing is never clobbered.
    _bodyController = TextEditingController(text: widget.viewModel.body);
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photos = widget.note.attachments
        .where((a) => a.kind == NoteAttachmentKind.photo)
        .toList();
    final audio = widget.note.attachments
        .where((a) => a.kind == NoteAttachmentKind.audio)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(kSize16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (photos.isNotEmpty) ...[
            _PhotoStrip(viewModel: widget.viewModel, photos: photos),
            verticalSpaceSmall,
          ],
          for (final a in audio) ...[
            _AudioRow(viewModel: widget.viewModel, attachment: a),
            verticalSpaceSmall,
          ],
          // flutter-only: multiline note body (maxLines: null, borderless custom
          // style). KitNativeTextField is a single-line credential/search field —
          // a scrolling note body is outside the native text-field's scope.
          // ponytail: uniform body style for the whole field — a real title/body
          // split would need a rich-text controller; iOS Notes just bolds line 1.
          TextField(
            controller: _bodyController,
            onChanged: widget.viewModel.onBodyChanged,
            autofocus: widget.note.body.isEmpty,
            keyboardType: TextInputType.multiline,
            maxLines: null,
            minLines: 8,
            style: theme.textTheme.bodyLarge,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Note',
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.viewModel, required this.photos});
  final ShowcaseNoteEditorViewModel viewModel;
  final List<NoteAttachment> photos;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 84,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: photos.length,
          separatorBuilder: (_, __) => horizontalSpaceSmall,
          itemBuilder: (context, i) {
            final attachment = photos[i];
            return FutureBuilder<String>(
              future: viewModel.resolvePath(attachment),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const SizedBox(
                    width: 84,
                    height: 84,
                    child: Center(child: KitNativeLoadingIndicator(size: 20)),
                  );
                }
                final file = File(snap.data!);
                return GestureDetector(
                  onTap: () => _openViewer(context, file),
                  onLongPress: () =>
                      _confirmRemove(context, viewModel, attachment),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(kRad12),
                    child: Image.file(
                      file,
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              },
            );
          },
        ),
      );

  void _openViewer(BuildContext context, File file) => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          // ponytail: media lightboxes are always black regardless of theme —
          // a deliberate platform constant, not a theme leak.
          backgroundColor: kcBlack,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(child: Image.file(file)),
              ),
              Positioned(
                top: kSize8,
                right: kSize8,
                child: KitNativeIconButton(
                  glyph: KitGlyphs.close,
                  color: kcWhite,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      );
}

Future<void> _confirmRemove(
  BuildContext context,
  ShowcaseNoteEditorViewModel viewModel,
  NoteAttachment attachment,
) async {
  if (await confirmDialog(context,
      title: 'Remove attachment?', actionLabel: 'Remove')) {
    await viewModel.removeAttachment(attachment);
  }
}

class _AudioRow extends StatelessWidget {
  const _AudioRow({required this.viewModel, required this.attachment});
  final ShowcaseNoteEditorViewModel viewModel;
  final NoteAttachment attachment;

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
      onLongPress: () => _confirmRemove(context, viewModel, attachment),
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
            Text(total == null ? '--:--' : _fmtDuration(total)),
          ],
        ),
      ),
    );
  }
}

class _BottomToolbar extends StatelessWidget {
  const _BottomToolbar({required this.viewModel});
  final ShowcaseNoteEditorViewModel viewModel;

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
                ? _RecordingRow(viewModel: viewModel)
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

class _RecordingRow extends StatelessWidget {
  const _RecordingRow({required this.viewModel});
  final ShowcaseNoteEditorViewModel viewModel;

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
                  _fmtDuration(elapsed),
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
