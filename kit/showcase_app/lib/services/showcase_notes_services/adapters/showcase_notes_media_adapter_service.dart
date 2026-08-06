import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:appbox_kit_media/appbox_kit_media.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart' show AppBoxKitActionOwner;
import 'package:uuid/uuid.dart';

import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_attachment_model.dart';

/// Owns attachment binaries and the recording/playback hardware for Notes.
///
/// A thin app-layer adapter over `appbox_kit_media`'s framework-free ports
/// ([AppBoxKitMediaCaptureService], [AppBoxKitAudioRecorderService], [AppBoxKitAudioPlayerService]) — it
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
/// Every hardware/IO operation dispatches on the owner's AppBoxKitAction
/// bus (one-shot `run`s): a plugin or file-system failure surfaces as an
/// error snackbar and collapses to the method's existing null/false contract
/// (fallback) instead of escaping uncaught. Expected non-error outcomes
/// (permission denial, user cancel) stay plain returns — no snackbar.
/// [resolvePath] stays raw: it is a pure path derivation on the
/// per-attachment render path, where a snackbar per failed row would storm.
class ShowcaseNotesMediaAdapterService with AppBoxKitActionOwner {
  /// Ports default to their real plugin-backed implementations; inject fakes
  /// (from `package:appbox_kit_media/appbox_kit_testing.dart`) in tests.
  ShowcaseNotesMediaAdapterService({
    AppBoxKitMediaCaptureService? capture,
    AppBoxKitAudioRecorderService? recorder,
    AppBoxKitAudioPlayerService? player,
  })  : _capture = capture ?? AppBoxKitImagePickerMediaCaptureService(),
        _recorder = recorder ?? AppBoxKitRecordAudioRecorderService(),
        _player = player ?? AppBoxKitJustAudioPlayerService() {
    // Mirror the kit ports' streams onto app-owned BehaviorSubjects, subscribed
    // here at construction so late-binding viewmodels still get the last value.
    // One watch per stream (each dispatchers to a different subject) — all
    // owner-keyed, so [dispose]'s disposeAppBoxKitActions() cancels them.
    watch('bridge.elapsed', streams: [_recorder.elapsed$], callback: (value) => recording$.add(value as Duration?));
    watch('bridge.position', streams: [_player.position$], callback: (value) => _position.add(value as Duration));
    watch('bridge.duration', streams: [_player.duration$], callback: (value) => _duration.add(value as Duration?));
    watch('bridge.state', streams: [_player.state$], callback: (value) => _playerState.add(value as AppBoxKitPlaybackState));
  }

  static const _uuid = Uuid();

  final AppBoxKitMediaCaptureService _capture;
  final AppBoxKitAudioRecorderService _recorder;
  final AppBoxKitAudioPlayerService _player;

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
  final BehaviorSubject<AppBoxKitPlaybackState> _playerState =
      BehaviorSubject<AppBoxKitPlaybackState>.seeded(AppBoxKitPlaybackState.idle);

  Stream<Duration> get position$ => _position.stream;
  Stream<Duration?> get duration$ => _duration.stream;
  Stream<AppBoxKitPlaybackState> get playerState$ => _playerState.stream;

  /// The iOS Simulator has no camera hardware, and capture throws when asked
  /// for the camera there. The kit's [AppBoxKitMediaCaptureService.hasCamera] detects
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
  /// collapses to null too, via the AppBoxKitAction fallback, after an error
  /// snackbar.
  Future<ShowcaseNoteAttachmentModel?> pickPhoto({required bool fromCamera}) =>
      bus.run<ShowcaseNoteAttachmentModel?>(
        'pickPhoto',
        () async {
          // Degrade to the library on simulators rather than crash — mirrors how
          // the UI hides the camera action via [isCameraAvailable].
          final source = (fromCamera && _capture.hasCamera)
              ? AppBoxKitMediaSource.camera
              : AppBoxKitMediaSource.gallery;
          final result = await _capture.capturePhoto(
            source: source,
            // Bounded so seed-snapshot-era demo photos don't balloon the docs dir.
            maxWidth: 2048,
            imageQuality: 85,
          );
          if (result is! AppBoxKitMediaCaptured) return null; // cancelled / denied / failed
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
        errorNotification: 'Could not add photo',
        errorMessage: 'Photo capture failed',
        withValue: null,
      );

  // -- Voice memos -------------------------------------------------------------

  /// False on permission denial (the view surfaces that — not an error, no
  /// snackbar); a recorder/plugin throw also collapses to false, after an
  /// error snackbar.
  Future<bool> startRecording() => bus.run<bool>(
        'startRecording',
        () async {
          if (!await _recorder.hasPermission()) return false;
          await _player.stop();
          playingAttachmentId$.add(null);

          final dir = await _attachmentsDir();
          // Encoder is aacLc → .m4a inside the kit, matching iOS voice memos.
          await _recorder.start(path: '${dir.path}/${_uuid.v4()}.m4a');
          return true;
        },
        errorNotification: 'Could not start recording',
        errorMessage: 'Recording start failed',
        withValue: false,
      );

  Future<ShowcaseNoteAttachmentModel?> stopRecording() =>
      bus.run<ShowcaseNoteAttachmentModel?>(
        'stopRecording',
        () async {
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
        errorNotification: 'Could not save voice memo',
        errorMessage: 'Recording stop failed',
        withValue: null,
      );

  Future<void> cancelRecording() => bus.run<void>(
        'cancelRecording',
        () => _recorder.cancel(),
        errorNotification: 'Could not cancel recording',
        errorMessage: 'Recording cancel failed',
      );

  // -- Playback ----------------------------------------------------------------

  /// Play [attachment] from the start, or toggle pause/resume when it is the
  /// one already loaded.
  Future<void> togglePlayback(ShowcaseNoteAttachmentModel attachment) =>
      bus.run<void>(
        'playback.${attachment.id}',
        () async {
          if (playingAttachmentId$.value == attachment.id) {
            _player.isPlaying ? await _player.pause() : await _player.play();
            return;
          }
          await _player.stop();
          await _player.setFilePath(await resolvePath(attachment));
          playingAttachmentId$.add(attachment.id);
          await _player.play();
        },
        errorNotification: 'Could not play voice memo',
        errorMessage: 'Playback failed',
      );

  Future<void> stopPlayback() async {
    await _player.stop();
    playingAttachmentId$.add(null);
  }

  /// Best-effort binary cleanup when an attachment is removed from a note.
  Future<void> deleteFile(ShowcaseNoteAttachmentModel attachment) =>
      bus.run<void>(
        'deleteFile.${attachment.id}',
        () async {
          if (playingAttachmentId$.value == attachment.id) await stopPlayback();
          final file = File(await resolvePath(attachment));
          if (await file.exists()) await file.delete();
        },
        errorNotification: 'Could not delete attachment',
        errorMessage: 'Attachment cleanup failed',
      );

  Future<void> dispose() async {
    disposeAppBoxKitActions();
    await _recorder.dispose();
    await _player.dispose();
    await recording$.close();
    await playingAttachmentId$.close();
    await _position.close();
    await _duration.close();
    await _playerState.close();
  }
}
