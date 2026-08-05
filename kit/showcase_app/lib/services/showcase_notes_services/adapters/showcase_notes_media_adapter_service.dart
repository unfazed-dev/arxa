import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:appbox_kit_media/appbox_kit_media.dart';
import 'package:uuid/uuid.dart';

import 'package:appbox_kit_showcase_app/models/showcase_notes_models/showcase_note_attachment_model.dart';

/// Owns attachment binaries and the recording/playback hardware for Notes.
///
/// A thin app-layer adapter over `appbox_kit_media`'s framework-free ports
/// ([MediaCaptureService], [AudioRecorderService], [AudioPlayerService]) — it
/// keeps the Notes-specific bits the kit deliberately stays out of: the
/// attachments directory, [ShowcaseNoteAttachmentModel] mapping, "which memo is playing"
/// tracking, and the "starting a recording stops playback" orchestration.
///
/// Files live under `<documents>/appbox_kit_showcase_app/attachments/`; rows
/// only carry the file NAME ([ShowcaseNoteAttachmentModel.fileName]) because the iOS app
/// container path changes across reinstalls — [resolvePath] re-derives the
/// absolute path each session.
///
/// One recorder and one player for the whole app: iOS Notes plays a single
/// memo at a time, and starting a recording stops playback.
class ShowcaseNotesMediaAdapterService {
  /// Ports default to their real plugin-backed implementations; inject fakes
  /// (from `package:appbox_kit_media/testing.dart`) in tests.
  ShowcaseNotesMediaAdapterService({
    MediaCaptureService? capture,
    AudioRecorderService? recorder,
    AudioPlayerService? player,
  })  : _capture = capture ?? ImagePickerMediaCaptureService(),
        _recorder = recorder ?? RecordAudioRecorderService(),
        _player = player ?? JustAudioPlayerService() {
    // Mirror the kit ports' streams onto app-owned BehaviorSubjects, subscribed
    // here at construction so late-binding viewmodels still get the last value.
    _subs = [
      _recorder.elapsed$.listen(recording$.add),
      _player.position$.listen(_position.add),
      _player.duration$.listen(_duration.add),
      _player.state$.listen(_playerState.add),
    ];
  }

  static const _uuid = Uuid();

  final MediaCaptureService _capture;
  final AudioRecorderService _recorder;
  final AudioPlayerService _player;

  late final List<StreamSubscription<Object?>> _subs;

  /// Elapsed recording time while recording, null otherwise — drives the
  /// editor's red recording pill.
  final BehaviorSubject<Duration?> recording$ =
      BehaviorSubject<Duration?>.seeded(null);

  /// Attachment id currently loaded in the player, null when idle — lets each
  /// memo card show play/pause for itself only.
  final BehaviorSubject<String?> playingAttachmentId$ =
      BehaviorSubject<String?>.seeded(null);

  final BehaviorSubject<Duration> _position =
      BehaviorSubject<Duration>.seeded(Duration.zero);
  final BehaviorSubject<Duration?> _duration =
      BehaviorSubject<Duration?>.seeded(null);
  final BehaviorSubject<PlaybackState> _playerState =
      BehaviorSubject<PlaybackState>.seeded(PlaybackState.idle);

  Stream<Duration> get position$ => _position.stream;
  Stream<Duration?> get duration$ => _duration.stream;
  Stream<PlaybackState> get playerState$ => _playerState.stream;

  /// The iOS Simulator has no camera hardware, and capture throws when asked
  /// for the camera there. The kit's [MediaCaptureService.hasCamera] detects
  /// this (via the injected `SIMULATOR_*` env vars) without a MethodChannel.
  /// ViewModels use this to hide the "Take Photo" action so the demo stays
  /// testable end-to-end on simulators.
  bool get isCameraAvailable => _capture.hasCamera;

  Future<Directory> _attachmentsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/appbox_kit_showcase_app/attachments');
    await dir.create(recursive: true);
    return dir;
  }

  Future<String> resolvePath(ShowcaseNoteAttachmentModel attachment) async {
    final dir = await _attachmentsDir();
    return '${dir.path}/${attachment.fileName}';
  }

  // -- Photos ----------------------------------------------------------------

  /// Camera capture or library pick. The kit returns a TEMP file — it is moved
  /// into the attachments dir or it would vanish with the cache. Permission
  /// denial, cancellation and missing hardware all collapse to null here (the
  /// UI already gates the camera via [isCameraAvailable]).
  Future<ShowcaseNoteAttachmentModel?> pickPhoto({required bool fromCamera}) async {
    // Degrade to the library on simulators rather than crash — mirrors how
    // the UI hides the camera action via [isCameraAvailable].
    final source = (fromCamera && _capture.hasCamera)
        ? MediaSource.camera
        : MediaSource.gallery;
    final result = await _capture.capturePhoto(
      source: source,
      // Bounded so seed-snapshot-era demo photos don't balloon the docs dir.
      maxWidth: 2048,
      imageQuality: 85,
    );
    if (result is! MediaCaptured) return null; // cancelled / denied / failed
    final media = result.media;

    final id = _uuid.v4();
    final extension = media.path.contains('.')
        ? media.path.substring(media.path.lastIndexOf('.'))
        : '.jpg';
    final fileName = '$id$extension';
    final dir = await _attachmentsDir();
    await media.saveTo('${dir.path}/$fileName');

    return ShowcaseNoteAttachmentModel(
      id: id,
      kind: ShowcaseNoteAttachmentKind.photo,
      fileName: fileName,
      createdAt: DateTime.now().toUtc(),
    );
  }

  // -- Voice memos -------------------------------------------------------------

  Future<bool> startRecording() async {
    if (!await _recorder.hasPermission()) return false;
    await _player.stop();
    playingAttachmentId$.add(null);

    final dir = await _attachmentsDir();
    // Encoder is aacLc → .m4a inside the kit, matching iOS voice memos.
    await _recorder.start(path: '${dir.path}/${_uuid.v4()}.m4a');
    return true;
  }

  Future<ShowcaseNoteAttachmentModel?> stopRecording() async {
    final result = await _recorder.stop();
    if (result == null) return null;
    return ShowcaseNoteAttachmentModel(
      id: _uuid.v4(),
      kind: ShowcaseNoteAttachmentKind.audio,
      fileName: result.path.substring(result.path.lastIndexOf('/') + 1),
      durationMs: result.duration.inMilliseconds,
      createdAt: DateTime.now().toUtc(),
    );
  }

  Future<void> cancelRecording() => _recorder.cancel();

  // -- Playback ----------------------------------------------------------------

  /// Play [attachment] from the start, or toggle pause/resume when it is the
  /// one already loaded.
  Future<void> togglePlayback(ShowcaseNoteAttachmentModel attachment) async {
    if (playingAttachmentId$.value == attachment.id) {
      _player.isPlaying ? await _player.pause() : await _player.play();
      return;
    }
    await _player.stop();
    await _player.setFilePath(await resolvePath(attachment));
    playingAttachmentId$.add(attachment.id);
    await _player.play();
  }

  Future<void> stopPlayback() async {
    await _player.stop();
    playingAttachmentId$.add(null);
  }

  /// Best-effort binary cleanup when an attachment is removed from a note.
  Future<void> deleteFile(ShowcaseNoteAttachmentModel attachment) async {
    if (playingAttachmentId$.value == attachment.id) await stopPlayback();
    final file = File(await resolvePath(attachment));
    if (await file.exists()) await file.delete();
  }

  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    await _recorder.dispose();
    await _player.dispose();
    await recording$.close();
    await playingAttachmentId$.close();
    await _position.close();
    await _duration.close();
    await _playerState.close();
  }
}
