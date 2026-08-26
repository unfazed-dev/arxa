/// A widget is a reusable UI piece composed by views. It receives data via
/// constructor params or [ArxaKitStreamBuilder] bindings and renders its
/// slice of the surface — it holds no business logic and never decides when
/// an action runs.
///
/// This is the user interface for the note editor's scrollable body — the text
/// field, photo strip, and audio rows. It owns a TextEditingController for the
/// borderless multiline document (seeded once from the VM, then one-way out via
/// onChanged for autosave).
///
/// Requirements:
/// 1. [Text editing] — edit-a-note
/// The multiline text field seeds once from the VM and calls onBodyChanged on
/// every keystroke.
/// 2. [Photo display] — attach-a-photo-to-a-note
/// The photo strip shows attached photos at the top of the body.
/// 3. [Audio display] — play-back-an-audio-attachment
/// Each audio attachment renders as a row with play/pause and live progress.
///
/// Relationships:
///
///   ┌──────────────────────────────┐
///   │   note editor body widget    │
///   └──────────────────────────────┘
///   ACT ▼
///   [1]
///   ┌──────────────────────────────┐
///   │    note editor viewmodel     │
///   └──────────────────────────────┘
///      ════════ abxAction ════════
///
///  actions (ACT)
///    1. onBodyChanged
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_notes_widgets/showcase_note_editor_body_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:arxa_kit_showcase_app/enums/showcase_notes_enums/enums.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';

class ShowcaseNoteEditorBodyWidget extends StatefulWidget {
  const ShowcaseNoteEditorBodyWidget({
    super.key,
    required this.viewModel,
    required this.note,
  });
  final ShowcaseNoteEditorViewModel viewModel;
  final ShowcaseNoteModel note;

  @override
  State<ShowcaseNoteEditorBodyWidget> createState() =>
      _ShowcaseNoteEditorBodyState();
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
      padding: const EdgeInsets.all(abxSize16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (photos.isNotEmpty) ...[
            ShowcaseNotePhotoStripWidget(
              viewModel: widget.viewModel,
              photos: photos,
            ),
            arxaKitVerticalSpaceSmall,
          ],
          for (final a in audio) ...[
            ShowcaseNoteAudioRowWidget(
              viewModel: widget.viewModel,
              attachment: a,
            ),
            arxaKitVerticalSpaceSmall,
          ],
          // flutter-only: multiline note body (maxLines: null, borderless custom
          // style). ArxaKitNativeTextField is a single-line credential/search field —
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
