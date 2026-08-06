import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:appbox_kit_media/appbox_kit_media.dart';
import 'package:ui_library/ui_library.dart' show KitAction;
import 'package:uuid/uuid.dart';

import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_attachment_model.dart';

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
///
/// Every hardware/IO operation runs through a KitAction chain: a plugin or
/// file-system failure surfaces as an error snackbar and collapses to the
/// method's existing null/false contract (fallback) instead of escaping
/// uncaught. Expected non-error outcomes (permission denial, user cancel)
/// stay plain returns — no snackbar. [resolvePath] stays raw: it is a pure
/// path derivation on the per-attachment render path, where a snackbar per
/// failed row would storm.
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
    // One KitAction.watch per stream (each pipes to a different subject) — all
    // owner-keyed, so [dispose]'s KitAction.disposeOwner(this) cancels them.
    KitAction.watch(owner: this, op: 'bridge.elapsed', streams: [_recorder.elapsed$], callback: (v) => recording$.add(v as Duration?));
    KitAction.watch(owner: this, op: 'bridge.position', streams: [_player.position$], callback: (v) => _position.add(v as Duration));
    KitAction.watch(owner: this, op: 'bridge.duration', streams: [_player.duration$], callback: (v) => _duration.add(v as Duration?));
    KitAction.watch(owner: this, op: 'bridge.state', streams: [_player.state$], callback: (v) => _playerState.add(v as PlaybackState));
  }

  static const _uuid = Uuid();

  final MediaCaptureService _capture;
  final AudioRecorderService _recorder;
  final AudioPlayerService _player;

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
  /// UI already gates the camera via [isCameraAvailable]); a plugin/IO throw
  /// collapses to null too, via the KitAction fallback, after an error
  /// snackbar.
  Future<ShowcaseNoteAttachmentModel?> pickPhoto({required bool fromCamera}) =>
      KitAction.run<ShowcaseNoteAttachmentModel?>(
        operation: () async {
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
        },
        owner: this,
        op: 'pickPhoto',
      )
          .withErrorSnackbar('Could not add photo')
          .withErrorFallback('Photo capture failed', fallback: null)
          .execute();

  // -- Voice memos -------------------------------------------------------------

  /// False on permission denial (the view surfaces that — not an error, no
  /// snackbar); a recorder/plugin throw also collapses to false, after an
  /// error snackbar.
  Future<bool> startRecording() => KitAction.run<bool>(
        operation: () async {
          if (!await _recorder.hasPermission()) return false;
          await _player.stop();
          playingAttachmentId$.add(null);

          final dir = await _attachmentsDir();
          // Encoder is aacLc → .m4a inside the kit, matching iOS voice memos.
          await _recorder.start(path: '${dir.path}/${_uuid.v4()}.m4a');
          return true;
        },
        owner: this,
        op: 'startRecording',
      )
          .withErrorSnackbar('Could not start recording')
          .withErrorFallback('Recording start failed', fallback: false)
          .execute();

  Future<ShowcaseNoteAttachmentModel?> stopRecording() =>
      KitAction.run<ShowcaseNoteAttachmentModel?>(
        operation: () async {
          final result = await _recorder.stop();
          if (result == null) return null;
          return ShowcaseNoteAttachmentModel(
            id: _uuid.v4(),
            kind: ShowcaseNoteAttachmentKind.audio,
            fileName: result.path.substring(result.path.lastIndexOf('/') + 1),
            durationMs: result.duration.inMilliseconds,
            createdAt: DateTime.now().toUtc(),
          );
        },
        owner: this,
        op: 'stopRecording',
      )
          .withErrorSnackbar('Could not save voice memo')
          .withErrorFallback('Recording stop failed', fallback: null)
          .execute();

  Future<void> cancelRecording() => KitAction.run<void>(
        operation: () => _recorder.cancel(),
        owner: this,
        op: 'cancelRecording',
      )
          .withErrorSnackbar('Could not cancel recording')
          .withErrorFallback('Recording cancel failed')
          .execute();

  // -- Playback ----------------------------------------------------------------

  /// Play [attachment] from the start, or toggle pause/resume when it is the
  /// one already loaded.
  Future<void> togglePlayback(ShowcaseNoteAttachmentModel attachment) =>
      KitAction.run<void>(
        operation: () async {
          if (playingAttachmentId$.value == attachment.id) {
            _player.isPlaying ? await _player.pause() : await _player.play();
            return;
          }
          await _player.stop();
          await _player.setFilePath(await resolvePath(attachment));
          playingAttachmentId$.add(attachment.id);
          await _player.play();
        },
        owner: this,
        op: 'playback.${attachment.id}',
      )
          .withErrorSnackbar('Could not play voice memo')
          .withErrorFallback('Playback failed')
          .execute();

  Future<void> stopPlayback() async {
    await _player.stop();
    playingAttachmentId$.add(null);
  }

  /// Best-effort binary cleanup when an attachment is removed from a note.
  Future<void> deleteFile(ShowcaseNoteAttachmentModel attachment) =>
      KitAction.run<void>(
        operation: () async {
          if (playingAttachmentId$.value == attachment.id) await stopPlayback();
          final file = File(await resolvePath(attachment));
          if (await file.exists()) await file.delete();
        },
        owner: this,
        op: 'deleteFile.${attachment.id}',
      )
          .withErrorSnackbar('Could not delete attachment')
          .withErrorFallback('Attachment cleanup failed')
          .execute();

  Future<void> dispose() async {
    KitAction.disposeOwner(this);
    await _recorder.dispose();
    await _player.dispose();
    await recording$.close();
    await playingAttachmentId$.close();
    await _position.close();
    await _duration.close();
    await _playerState.close();
  }
}
