import 'dart:async';

import 'package:rxdart/rxdart.dart' show Rx;
import 'package:stacked/stacked.dart';
import 'package:appbox_kit_media/appbox_kit_media.dart' show PlaybackState;
import 'package:appbox_kit_core/kit_locator.dart';

import 'package:appbox_kit_showcase_app/notes/models/note.dart';
import 'package:appbox_kit_showcase_app/notes/models/note_attachment.dart';
import 'package:appbox_kit_showcase_app/services/notes_media_service.dart';
import 'package:appbox_kit_showcase_app/services/facades/notes_facade.dart';

/// Live playback progress for the audio scrubber — position paired with the
/// player-reported track length. Consumed by the view via [KitStreamBuilder]
/// so high-frequency position ticks rebuild only the progress bar, not the
/// whole editor.
typedef NotePlaybackProgress = ({Duration position, Duration? duration});

/// The note editor, route `/showcase/notes/note/:id`. Owns the body text as a
/// plain [String] (logic-only — no `TextEditingController` in the viewmodel,
/// which would drag a `package:flutter/*` import in here, kit-reviewer 1m).
/// The view's body field owns its own [TextEditingController] for IME/cursor
/// lifecycle and seeds from [body]; the value mirror here drives debounced
/// autosave. Mirrors [NotesMediaService]'s recording/playback streams for the
/// editor chrome.
class ShowcaseNoteEditorViewModel extends BaseViewModel {
  ShowcaseNoteEditorViewModel({required this.noteId}) {
    _noteSub = _notes.note$(noteId).listen(_onNote);
    _recordingSub = _media.recording$.listen((d) {
      recordingElapsed = d;
      notifyListeners();
    });
    _playingSub = _media.playingAttachmentId$.listen((id) {
      playingAttachmentId = id;
      notifyListeners();
    });
    _playerStateSub = _media.playerState$.listen((s) {
      playerState = s;
      notifyListeners();
    });
  }

  final String noteId;

  final NotesFacade _notes = locator<NotesFacade>();
  final NotesMediaService _media = locator<NotesMediaService>();

  /// The note body. Seeded once from the first note$ emit; subsequent emits
  /// (attachment add/remove, pin toggle, autosave write-back) must not clobber
  /// what the user is typing, so the seed is one-shot ([_textInitialized]).
  /// The view's body field reads this to seed its own controller.
  String _body = '';
  String get body => _body;

  late final StreamSubscription<Note?> _noteSub;
  late final StreamSubscription<Duration?> _recordingSub;
  late final StreamSubscription<String?> _playingSub;
  late final StreamSubscription<PlaybackState> _playerStateSub;

  Timer? _saveDebounce;
  // Set once, from the first note$ emit — every later emit must not clobber
  // the value the user is typing.
  bool _textInitialized = false;

  /// One-shot intent set by the Folders FAB menu before it navigates here:
  /// `'camera'` (New Photo) or `'mic'` (New Voice), consumed on first note
  /// load. ponytail: module-level single-slot — fine for single-user
  /// sequential navigation; not safe for concurrent editor opens.
  static String? pendingAction;
  bool _pendingHandled = false;

  Note? note;
  Duration? recordingElapsed;
  String? playingAttachmentId;
  PlaybackState? playerState;

  bool get isRecording => recordingElapsed != null;

  bool isAttachmentPlaying(String attachmentId) =>
      playingAttachmentId == attachmentId && (playerState?.playing ?? false);

  /// Combined position + track length for the audio scrubber. Both back onto
  /// seeded [BehaviorSubject]s in [NotesMediaService], so this replays the
  /// current values on subscribe; the view seeds [KitStreamBuilder] with a
  /// zeroed record to paint the first frame without a loading flash.
  Stream<NotePlaybackProgress> get playbackProgress$ => Rx.combineLatest2(
        _media.position$,
        _media.duration$,
        (Duration p, Duration? d) => (position: p, duration: d),
      );

  void _onNote(Note? n) {
    note = n;
    if (!_textInitialized) {
      _body = n?.body ?? '';
      _textInitialized = true;
    }
    notifyListeners();
    _maybeRunPendingAction();
  }

  /// Runs [pendingAction] once the note has loaded, then clears it. New Photo
  /// auto-opens the camera (skipped where unavailable, e.g. the iOS Simulator);
  /// New Voice starts a recording.
  Future<void> _maybeRunPendingAction() async {
    if (_pendingHandled || note == null || pendingAction == null) return;
    _pendingHandled = true;
    final action = pendingAction;
    pendingAction = null;
    if (action == 'camera' && isCameraAvailable) {
      await addPhoto(fromCamera: true);
    } else if (action == 'mic') {
      await startRecording();
    }
  }

  Future<String> resolvePath(NoteAttachment attachment) =>
      _media.resolvePath(attachment);

  void onBodyChanged(String value) {
    _body = value;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), _flushSave);
  }

  Future<void> _flushSave() async {
    final current = note;
    if (current == null) return;
    await _notes.saveBody(current, _body);
  }

  Future<void> togglePin() async {
    final current = note;
    if (current == null) return;
    await _notes.togglePin(current);
  }

  Future<void> delete() async {
    final current = note;
    if (current == null) return;
    await _notes.moveToTrash(current);
  }

  /// False on the iOS Simulator, where camera capture is unavailable — the
  /// toolbar hides the camera action so every visible control works.
  bool get isCameraAvailable => _media.isCameraAvailable;

  Future<void> addPhoto({required bool fromCamera}) async {
    final attachment = await _media.pickPhoto(fromCamera: fromCamera);
    final current = note;
    if (attachment == null || current == null) return;
    await _notes.addAttachment(current, attachment);
  }

  Future<void> removeAttachment(NoteAttachment attachment) async {
    final current = note;
    if (current == null) return;
    await _notes.removeAttachment(current, attachment.id);
    await _media.deleteFile(attachment);
  }

  /// Returns false on permission denial — the view surfaces that.
  Future<bool> startRecording() => _media.startRecording();

  Future<void> stopRecording() async {
    final attachment = await _media.stopRecording();
    final current = note;
    if (attachment == null || current == null) return;
    await _notes.addAttachment(current, attachment);
  }

  Future<void> cancelRecording() => _media.cancelRecording();

  Future<void> togglePlayback(NoteAttachment attachment) =>
      _media.togglePlayback(attachment);

  @override
  void dispose() {
    // Clear any unconsumed intent so it can't leak into the next editor open.
    pendingAction = null;
    if (_saveDebounce?.isActive ?? false) {
      _saveDebounce!.cancel();
      _flushSave(); // best-effort — dispose can't await
    }
    _saveDebounce?.cancel();
    _noteSub.cancel();
    _recordingSub.cancel();
    _playingSub.cancel();
    _playerStateSub.cancel();
    super.dispose();
  }
}
