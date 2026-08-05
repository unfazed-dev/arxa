import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/models/showcase_note.dart';
import 'package:appbox_kit_showcase_app/models/showcase_note_attachment.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';

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
class ShowcaseNoteEditorBodyWidget extends StatefulWidget {
  const ShowcaseNoteEditorBodyWidget({
    super.key,
    required this.viewModel,
    required this.note,
    required this.onRemoveAttachment,
    required this.formatDuration,
  });
  final ShowcaseNoteEditorViewModel viewModel;
  final ShowcaseNote note;

  /// Long-press handler for an attachment — the view owns the
  /// remove-confirmation dialog plumbing.
  final Future<void> Function(ShowcaseNoteAttachment attachment) onRemoveAttachment;

  /// Duration label formatter — the view owns the formatting helper.
  final String Function(Duration duration) formatDuration;

  @override
  State<ShowcaseNoteEditorBodyWidget> createState() => _ShowcaseNoteEditorBodyState();
}

class _ShowcaseNoteEditorBodyState extends State<ShowcaseNoteEditorBodyWidget> {
  late final TextEditingController _bodyController;

  @override
  void initState() {
    super.initState();
    // Seed once from the VM's loaded body. The parent only mounts
    // ShowcaseNoteEditorBodyWidget once note != null, so viewModel.body is the
    // loaded body here. The VM never writes this controller again — typing
    // flows OUT via onChanged, and external note updates (attachments/pin)
    // don't re-seed (VM's _textInitialized guard), so user typing is never
    // clobbered.
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
        .where((a) => a.kind == ShowcaseNoteAttachmentKind.photo)
        .toList();
    final audio = widget.note.attachments
        .where((a) => a.kind == ShowcaseNoteAttachmentKind.audio)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(kSize16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (photos.isNotEmpty) ...[
            ShowcaseNotePhotoStripWidget(
              viewModel: widget.viewModel,
              photos: photos,
              onRemoveAttachment: widget.onRemoveAttachment,
            ),
            verticalSpaceSmall,
          ],
          for (final a in audio) ...[
            ShowcaseNoteAudioRowWidget(
              viewModel: widget.viewModel,
              attachment: a,
              onRemoveAttachment: widget.onRemoveAttachment,
              formatDuration: widget.formatDuration,
            ),
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
