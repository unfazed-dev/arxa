/// The note editor's viewmodel (route `/showcase/notes/note/:id`). The view
/// calls actions in and reads streams out: when the user does something, the
/// matching action does the work; when something changes, the new value flows
/// down the stream and the view redraws just the part listening to it. The
/// viewmodel never touches the view — swap the UI for any other and this file
/// stays unchanged.
///
/// Requirements:
/// 1. [Text ownership] — edit-a-note
/// The viewmodel keeps the note's text as plain text.
/// 2. [Starting text] — edit-a-note
/// When the note first loads, the text is filled in once.
/// 3. [Autosave] — edit-a-note
/// When the text changes, it is saved automatically after a short pause.
/// 4. [Final save] — edit-a-note
/// When the editor closes, a waiting save happens right away.
/// 5. [Pinning] — pin-a-note-to-the-top-of-the-inbox / unpin-a-pinned-note
/// The note can be pinned or unpinned.
/// 6. [Move to trash] — trash-a-note
/// The note moves to Recently Deleted.
/// 7. [Attaching photos] — attach-a-photo-to-a-note
/// A photo, picked from the gallery or taken with the camera, joins the note.
/// 8. [Removing attachments] — attach-a-photo-to-a-note
/// When the user confirms, an attachment leaves the note and its file is deleted.
/// 9. [Recording voice notes] — attach-an-audio-recording-to-a-note
/// When a recording stops, it joins the note.
/// 10. [Discarding a recording] — attach-an-audio-recording-to-a-note
/// A recording in progress can be thrown away.
/// 11. [Playing audio] — play-back-an-audio-attachment
/// An audio attachment plays and pauses, with live progress.
/// 12. [Quick action] — attach-a-photo-to-a-note / attach-an-audio-recording-to-a-note
/// When the route carries a quick action, the editor starts it once the note loads.
/// 13. [Edited label] — edit-a-note
/// The app bar shows when the note was last edited.
///
/// Relationships:
///
///       ┌──────────────────┐
///       │ note editor view │
///       └──────────────────┘
///       ACT ▼        ▲ STRM
///       [1-13]       [1-6]
///   ┌─────────────────────────┐
///   │  note editor viewmodel  │
///   └─────────────────────────┘
///         ACT ▼    ▲ STRM
///        [1-10]    [1-6]
///         ┌──────────────┐
///         │ notes facade │
///         └──────────────┘
///   ════════ abxAction ════════
///
///  streams (STRM)            actions (ACT)              commands (CMD)
///    1. note$                  1. saveBody                1. `save` (autosave)
///    2. recording$             2. togglePin               2. `removeAttachment` (confirm gate)
///    3. playingAttachmentId$   3. moveToTrash
///    4. playerState$           4. addPhoto
///    5. isAttachmentPlaying$   5. addVoiceNote
///    6. playbackProgress$      6. removeAttachment
///                              7. startRecording
///                              8. cancelRecording
///                              9. togglePlayback
///                             10. resolvePath
///
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart
library;

import 'package:flutter/material.dart' show BuildContext, TimeOfDay;
import 'package:appbox_kit_media/appbox_kit_media.dart'
    show AppBoxKitPlaybackProgress, AppBoxKitPlaybackState;
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';

class ShowcaseNoteEditorViewModel extends AppBoxKitViewModel {
  // ── Setup ──────────────────────────────────────────────────────────────────

  ShowcaseNoteEditorViewModel({required this.noteId, this.quickAction}) {
    // One shared watch; the operators carry the latches — `take(1)` after
    // the null filter IS "once the note has loaded", no bool flags.
    final note$ = _notes.note$(noteId).shareValue();
    listen(
      'note.track',
      to: [note$],
      onData: (note) => _note = note as ShowcaseNoteModel?,
    );
    listen(
      'note.firstLoad',
      to: [note$.where((note) => note != null).take(1)],
      onData: (note) => _onFirstLoad(note as ShowcaseNoteModel),
    );
  }

  final String noteId;

  final ShowcaseNotesFacadeService _notes =
      appBoxKitLocator<ShowcaseNotesFacadeService>();

  // ── Initial state ─────────────────────────────────────────────────────────

  /// [1. Text ownership][2. Starting text] The note's text, filled in once on load.
  String _body = '';
  String get body => _body;

  /// [5. Pinning][6. Move to trash][7. Attaching photos][9. Recording voice notes]
  /// The latest note, kept on hand so the actions below never wait for it.
  ShowcaseNoteModel? _note;

  /// [12. Quick action] A one-time request carried by the route: `'camera'` or `'mic'`.
  final String? quickAction;

  /// [7. Attaching photos] False on the iOS Simulator, so the camera button hides.
  bool get isCameraAvailable => _notes.isCameraAvailable;

  // ── Streams ─────────────────────────────────────────────────────────

  /// [2. Starting text] The open note — empty while loading or once deleted.
  Stream<ShowcaseNoteModel?> get note$ => _notes.note$(noteId);

  /// [9. Recording voice notes] How long the current recording has been running.
  ValueStream<Duration?> get recordingElapsed$ => _notes.recording$;

  /// [11. Playing audio] Which attachment is loaded in the player, if any.
  ValueStream<String?> get playingAttachmentId$ => _notes.playingAttachmentId$;

  /// [11. Playing audio] Whether the player is playing, paused, or loading.
  Stream<AppBoxKitPlaybackState> get playerState$ => _notes.playerState$;

  /// [11. Playing audio] Whether this attachment is the one playing right now.
  Stream<bool> isAttachmentPlaying$(String attachmentId) =>
      _notes.isAttachmentPlaying$(attachmentId);

  /// [11. Playing audio] Live progress for the audio scrubber.
  Stream<AppBoxKitPlaybackProgress> get playbackProgress$ =>
      _notes.playbackProgress$;

  // ── Commands ─────────────────────────────────────────
  // Commands decide when — and whether — Actions run.

  /// [3. Autosave][4. Final save] Saves after a short pause in typing, and right
  /// away when the editor closes.
  late final _autosave = abxActionHub.on<Null, void>(
    'save',
    (_) => _flushSave(),
    debounce: const Duration(milliseconds: 500),
    errorMessage: 'Save failed',
    flushOnDispose: true,
  );

  /// [3. Autosave] Writes the current text to the note.
  Future<void> _flushSave() async {
    final current = _note;
    if (current == null) return;
    await _notes.saveBody(current, _body);
  }

  /// [8. Removing attachments] Asks first (the hub's confirm gate); on confirm
  /// the attachment leaves the note and its file is deleted — one facade call.
  late final _removeAttachment =
      abxActionHub.on<ShowcaseNoteAttachmentModel, void>(
    'removeAttachment',
    (attachment) async {
      final current = _note;
      if (current == null) return;
      await _notes.removeAttachment(current, attachment);
    },
    confirmTitle: 'Remove attachment?',
    confirmActionLabel: 'Remove',
  );

  // ── Actions ──────────────────────────────────────────

  /// [3. Autosave] The view calls this on every keystroke.
  void onBodyChanged(String value) {
    _body = value;
    _autosave.send(null);
  }

  /// [5. Pinning] Pins or unpins the note.
  Future<void> togglePin() async {
    final current = _note;
    if (current == null) return;
    await _notes.togglePin(current);
  }

  /// [6. Move to trash] Sends the note to Recently Deleted.
  Future<void> delete() async {
    final current = _note;
    if (current == null) return;
    await _notes.moveToTrash(current);
  }

  /// [8. Removing attachments] The view calls this from the attachment menu.
  Future<void> confirmRemoveAttachment(
          ShowcaseNoteAttachmentModel attachment) =>
      _removeAttachment.send(attachment);

  /// [7. Attaching photos] Picks or captures a photo and attaches it.
  Future<void> addPhoto({required bool fromCamera}) async {
    final current = _note;
    if (current == null) return;
    await _notes.addPhoto(current, fromCamera: fromCamera);
  }

  /// [9. Recording voice notes] Starts recording; false if permission was denied.
  Future<bool> startRecording() => _notes.startRecording();

  /// [9. Recording voice notes] Stops recording and attaches the voice note.
  Future<void> stopRecording() async {
    final current = _note;
    if (current == null) return;
    await _notes.addVoiceNote(current);
  }

  /// [10. Discarding a recording] Throws away the in-progress recording.
  Future<void> cancelRecording() => _notes.cancelRecording();

  /// [11. Playing audio] Plays or pauses an audio attachment.
  Future<void> togglePlayback(ShowcaseNoteAttachmentModel attachment) =>
      _notes.togglePlayback(attachment);

  /// [11. Playing audio] Where an attachment's file lives.
  Future<String> resolvePath(ShowcaseNoteAttachmentModel attachment) =>
      _notes.resolvePath(attachment);

  /// [13. Edited label] `Edited <time>` today, `Edited <date>` otherwise.
  String editedLabel(BuildContext context, DateTime updatedAt) {
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

  // ── Side effects ─────────────────────────────────────────────────────────

  /// [2. Starting text][12. Quick action] First load only (`take(1)`): fill
  /// the text once, run any quick action. Handles are pre-observed, so the
  /// fire-and-forget sends below are safe.
  void _onFirstLoad(ShowcaseNoteModel note) {
    _body = note.body;
    switch (quickAction) {
      case 'camera' when isCameraAvailable:
        addPhoto(fromCamera: true);
      case 'mic':
        startRecording();
    }
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  /// [4. Final save] A waiting save lands here on the way out (flushOnDispose).
  @override
  void dispose() => super.dispose();
}
