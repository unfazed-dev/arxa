import 'package:rxdart/rxdart.dart';
import 'package:appbox_kit_media/appbox_kit_media.dart' show AppBoxKitPlaybackState;
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_model.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_attachment_model.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/adapters/showcase_notes_media_adapter_service.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';

// The view knows its viewmodel ONLY — every type a view needs to name (the
// stream payloads) is re-exported here so view files never import services,
// repositories, or data/model packages directly.
export 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_model.dart';
export 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_attachment_model.dart';

/// Live playback progress for the audio scrubber — position paired with the
/// player-reported track length. Consumed by the view via [AppBoxKitStreamBuilder]
/// so high-frequency position ticks rebuild only the progress bar, not the
/// whole editor.
typedef NotePlaybackProgress = ({Duration position, Duration? duration});

/// The note editor, route `/showcase/notes/note/:id` — streams-only (house
/// convention): all state is exposed as streams and the views bind them with
/// [AppBoxKitStreamBuilder]; `BaseViewModel` is a lifecycle token (creation/disposal
/// via StackedView), never a rebuild mechanism — `notifyListeners` is not
/// called.
///
/// Owns the body text as a plain [String] (logic-only — no
/// `TextEditingController` in the viewmodel, which would drag a
/// `package:flutter/*` import in here, kit-reviewer 1m). The view's body
/// field owns its own [TextEditingController] for IME/cursor lifecycle and
/// seeds from [body]; the value mirror here drives debounced autosave.
///
/// [note$] is a facade pass-through; the media state streams are
/// pass-throughs of [ShowcaseNotesMediaAdapterService]'s seeded
/// [BehaviorSubject]s. The one [AppBoxKitAction.watch] left runs VM-internal side
/// effects only (the one-shot body seed and the pending New Photo/New Voice
/// intent) — it feeds no view data. Autosave debounce is the pipeline's
/// per-pipe `debounce`, not a hand-rolled Timer.
class ShowcaseNoteEditorViewModel extends AppBoxKitViewModel {
  ShowcaseNoteEditorViewModel({required this.noteId}) {
    watch(
      'note.sideEffects',
      streams: [_notes.note$(noteId)],
      callback: (note) => _onNoteSideEffects(note as ShowcaseNoteModel?),
    );
  }

  final String noteId;

  final ShowcaseNotesFacadeService _notes =
      appBoxKitLocator<ShowcaseNotesFacadeService>();
  final ShowcaseNotesMediaAdapterService _media =
      appBoxKitLocator<ShowcaseNotesMediaAdapterService>();

  /// The loaded note — null while loading or once deleted. The view binds the
  /// app bar and body to it.
  Stream<ShowcaseNoteModel?> get note$ => _notes.note$(noteId);

  // -- Media adapter pass-throughs --------------------------------------------
  // The adapter's state already lives on seeded BehaviorSubjects, so these
  // replay their current value to every AppBoxKitStreamBuilder that subscribes.

  /// Elapsed recording time while capturing, null otherwise — drives the
  /// toolbar's recording-row swap and the red elapsed pill.
  ValueStream<Duration?> get recordingElapsed$ => _media.recording$;

  /// Attachment id currently loaded in the player, null when idle.
  ValueStream<String?> get playingAttachmentId$ => _media.playingAttachmentId$;

  Stream<AppBoxKitPlaybackState> get playerState$ => _media.playerState$;

  /// Whether [attachmentId] is the loaded attachment AND playing — drives the
  /// row's play/pause glyph and gates its live progress subscription.
  Stream<bool> isAttachmentPlaying$(String attachmentId) => Rx.combineLatest2(
        playingAttachmentId$,
        playerState$,
        (String? id, AppBoxKitPlaybackState state) => id == attachmentId && state.playing,
      );

  /// Combined position + track length for the audio scrubber. Both back onto
  /// seeded [BehaviorSubject]s in [ShowcaseNotesMediaAdapterService], so this replays the
  /// current values on subscribe; the view seeds [AppBoxKitStreamBuilder] with a
  /// zeroed record to paint the first frame without a loading flash.
  Stream<NotePlaybackProgress> get playbackProgress$ => Rx.combineLatest2(
        _media.position$,
        _media.duration$,
        (Duration position, Duration? duration) =>
            (position: position, duration: duration),
      );

  /// The note body. Seeded once from the first note$ emit; subsequent emits
  /// (attachment add/remove, pin toggle, autosave write-back) must not clobber
  /// what the user is typing, so the seed is one-shot ([_textInitialized]).
  /// The view's body field reads this to seed its own controller.
  String _body = '';
  String get body => _body;

  // Set once, from the first note$ emit — every later emit must not clobber
  // the value the user is typing.
  bool _textInitialized = false;

  /// Command-side cache of the latest note$ event (togglePin/delete/attachment
  /// writes need it synchronously). Fed by the side-effect watch — the view
  /// never reads it; it binds [note$].
  ShowcaseNoteModel? _note;

  /// One-shot intent set by the Folders FAB menu before it navigates here:
  /// `'camera'` (New Photo) or `'mic'` (New Voice), consumed on first note
  /// load. ponytail: module-level single-slot — fine for single-user
  /// sequential navigation; not safe for concurrent editor opens.
  static String? pendingAction;
  bool _pendingHandled = false;

  /// VM-internal side effects for a note$ event: cache for commands, one-shot
  /// body seed, pending FAB intent. No view data — the view binds [note$].
  void _onNoteSideEffects(ShowcaseNoteModel? n) {
    _note = n;
    if (!_textInitialized) {
      _body = n?.body ?? '';
      _textInitialized = true;
    }
    _maybeRunPendingAction();
  }

  /// Runs [pendingAction] once the note has loaded, then clears it. New Photo
  /// auto-opens the camera (skipped where unavailable, e.g. the iOS Simulator);
  /// New Voice starts a recording.
  Future<void> _maybeRunPendingAction() async {
    if (_pendingHandled || _note == null || pendingAction == null) return;
    _pendingHandled = true;
    final pending = pendingAction;
    pendingAction = null;
    if (pending == 'camera' && isCameraAvailable) {
      await addPhoto(fromCamera: true);
    } else if (pending == 'mic') {
      await startRecording();
    }
  }

  Future<String> resolvePath(ShowcaseNoteAttachmentModel attachment) =>
      _media.resolvePath(attachment);

  /// Debounced autosave pipe: rapid keystrokes supersede the pending save and
  /// the superseded handles complete with the eventual save's result (the
  /// caller drops them — fire-and-forget by construction). The VM is
  /// per-note, so the entity key is implicit in the owner identity.
  /// `flushOnDispose` lands the final write: leaving the editor inside the
  /// debounce window saves immediately instead of dropping the keystrokes.
  late final _autosave = pipeline.pipe<Null, void>(
    'save',
    (_) => _flushSave(),
    debounce: const Duration(milliseconds: 500),
    errorMessage: 'Save failed',
    flushOnDispose: true,
  );

  void onBodyChanged(String value) {
    _body = value;
    _autosave.dispatch(null);
  }

  Future<void> _flushSave() async {
    final current = _note;
    if (current == null) return;
    await _notes.saveBody(current, _body);
  }

  Future<void> togglePin() async {
    final current = _note;
    if (current == null) return;
    await _notes.togglePin(current);
  }

  Future<void> delete() async {
    final current = _note;
    if (current == null) return;
    await _notes.moveToTrash(current);
  }

  /// False on the iOS Simulator, where camera capture is unavailable — the
  /// toolbar hides the camera action so every visible control works.
  bool get isCameraAvailable => _media.isCameraAvailable;

  Future<void> addPhoto({required bool fromCamera}) async {
    final attachment = await _media.pickPhoto(fromCamera: fromCamera);
    final current = _note;
    if (attachment == null || current == null) return;
    await _notes.addAttachment(current, attachment);
  }

  Future<void> removeAttachment(ShowcaseNoteAttachmentModel attachment) async {
    final current = _note;
    if (current == null) return;
    await _notes.removeAttachment(current, attachment.id);
    await _media.deleteFile(attachment);
  }

  /// Returns false on permission denial — the view surfaces that.
  Future<bool> startRecording() => _media.startRecording();

  Future<void> stopRecording() async {
    final attachment = await _media.stopRecording();
    final current = _note;
    if (attachment == null || current == null) return;
    await _notes.addAttachment(current, attachment);
  }

  Future<void> cancelRecording() => _media.cancelRecording();

  Future<void> togglePlayback(ShowcaseNoteAttachmentModel attachment) =>
      _media.togglePlayback(attachment);

  @override
  void dispose() {
    // Clear any unconsumed intent so it can't leak into the next editor open.
    pendingAction = null;
    // A pending debounced save is flushed by the pipe's flushOnDispose in
    // super.dispose() → disposeAppBoxKitActions.
    super.dispose();
  }
}
