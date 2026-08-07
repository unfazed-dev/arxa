/// The notes media adapter (app-layer). A thin bridge over the kit's
/// framework-free media ports — the facade calls actions in and reads streams
/// out, same as every app layer, but this one owns the device/hardware surface:
/// camera, recorder, player, plus the app-specific derivations the kit
/// deliberately stays out of (attachments directory, model mapping, "which memo
/// is playing" tracking, "starting a recording stops playback" orchestration).
/// Every hardware/IO op dispatches on the owner's AppBoxKitAction hub: a plugin
/// or file-system failure surfaces as an error snackbar and collapses to the
/// method's existing null/false contract instead of escaping uncaught.
///
/// This is the bridge to the device for note attachments. It takes photos with
/// the camera or picks them from the gallery, records voice memos, plays them
/// back, and manages the attachment files on disk — all so the rest of the app
/// never touches a plugin or file path directly.
///
/// Requirements:
/// 1. [Pick or capture photo] — search-and-attachments.media-attachments.attach-a-photo-to-a-note
/// Camera capture or gallery pick; the temp file moves into the attachments dir.
/// 2. [Record voice memo] — search-and-attachments.media-attachments.attach-an-audio-recording-to-a-note
/// A recording starts and stops; starting one stops any playback in progress.
/// 3. [Play back audio] — search-and-attachments.media-attachments.play-back-an-audio-attachment
/// An audio attachment plays and pauses, with live progress.
/// 4. [Attachment files]
/// Resolve a file path from its stored name and delete the binary on removal.
/// 5. [Camera detection]
/// Report whether the camera is available so the UI can hide the action on simulators.
///
/// Relationships:
///
///      ┌──────────────┐
///      │ notes facade │
///      └──────────────┘
///      ACT ▼    ▲ STRM
///      [1-7]    [1-5]
///   ┌─────────────────────┐
///   │ notes media adapter │
///   └─────────────────────┘
///     ┌─────────────────┐
///     │ kit media ports │
///     └─────────────────┘
/// ════════ abxAction ════════
///
///  streams (STRM)            actions (ACT)
///    1. recording$             1. pickPhoto
///    2. playingAttachmentId$   2. startRecording
///    3. playerState$           3. stopRecording
///    4. isAttachmentPlaying$   4. cancelRecording
///    5. playbackProgress$      5. togglePlayback
///                              6. deleteFile
///                              7. resolvePath
///
/// History: git log --follow -- kit/showcase_app/lib/services/showcase_notes_services/adapters/showcase_notes_media_adapter_service.dart
library;

import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:appbox_kit_media/appbox_kit_media.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart'
    show AppBoxKitActionOwner, BehaviorSubject, Rx;
import 'package:uuid/uuid.dart';

import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_attachment_model.dart';
import 'package:appbox_kit_showcase_app/enums/showcase_notes_enums/enums.dart';

class ShowcaseNotesMediaAdapterService with AppBoxKitActionOwner {
  // ── Setup ───────────────────────────────────────────────────────────────

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
    // One listen per stream (each commands to a different subject) — all
    // owner-keyed, so [dispose]'s disposeAppBoxKitActions() cancels them.
    listen('bridge.elapsed', to: [_recorder.elapsed$], onData: (value) => recording$.add(value as Duration?));
    listen('bridge.position', to: [_player.position$], onData: (value) => _position.add(value as Duration));
    listen('bridge.duration', to: [_player.duration$], onData: (value) => _duration.add(value as Duration?));
    listen('bridge.state', to: [_player.state$], onData: (value) => _playerState.add(value as AppBoxKitPlaybackState));
  }

  static const _uuid = Uuid();

  final AppBoxKitMediaCaptureService _capture;
  final AppBoxKitAudioRecorderService _recorder;
  final AppBoxKitAudioPlayerService _player;

  // ── Initial state ──────────────────────────────────────────────────────

  /// [2. Record voice memo] Elapsed recording time while recording, null
  /// otherwise — drives the editor's red recording pill.
  final BehaviorSubject<Duration?> recording$ =
      BehaviorSubject<Duration?>.seeded(null);

  /// [3. Play back audio] Attachment id currently loaded in the player, null
  /// when idle — lets each memo card show play/pause for itself only.
  final BehaviorSubject<String?> playingAttachmentId$ =
      BehaviorSubject<String?>.seeded(null);

  final BehaviorSubject<Duration> _position =
      BehaviorSubject<Duration>.seeded(Duration.zero);
  final BehaviorSubject<Duration?> _duration =
      BehaviorSubject<Duration?>.seeded(null);
  final BehaviorSubject<AppBoxKitPlaybackState> _playerState =
      BehaviorSubject<AppBoxKitPlaybackState>.seeded(AppBoxKitPlaybackState.idle);

  /// [5. Camera detection] The iOS Simulator has no camera hardware, and
  /// capture throws when asked for the camera there. The kit's
  /// [AppBoxKitMediaCaptureService.hasCamera] detects this (via the injected
  /// `SIMULATOR_*` env vars) without a MethodChannel. ViewModels use this to
  /// hide the "Take Photo" action so the demo stays testable end-to-end on
  /// simulators.
  bool get isCameraAvailable => _capture.hasCamera;

  // ── Streams ───────────────────────────────────────────────────────────

  /// [3. Play back audio] Player position, track length, and state, bridged
  /// from the kit ports onto app-owned subjects.
  Stream<Duration> get position$ => _position.stream;
  Stream<Duration?> get duration$ => _duration.stream;
  Stream<AppBoxKitPlaybackState> get playerState$ => _playerState.stream;

  /// [3. Play back audio] Whether [attachmentId] is the one loaded and playing
  /// right now — derived from the adapter's own player state, so any surface
  /// can ask.
  Stream<bool> isAttachmentPlaying$(String attachmentId) => Rx.combineLatest2(
        playingAttachmentId$,
        playerState$,
        (String? id, AppBoxKitPlaybackState state) =>
            id == attachmentId && state.playing,
      );

  /// [3. Play back audio] Live position paired with the track length, for a
  /// scrubber.
  Stream<AppBoxKitPlaybackProgress> get playbackProgress$ => Rx.combineLatest2(
        position$,
        duration$,
        (Duration position, Duration? duration) =>
            (position: position, duration: duration),
      );

  // ── Actions ────────────────────────────────────────────────────────────

  Future<Directory> _attachmentsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/appbox_kit_showcase_app/attachments');
    await dir.create(recursive: true);
    return dir;
  }

  /// [4. Attachment files] Re-derives the absolute path from the stored file
  /// name — the iOS app container path changes across reinstalls, so only the
  /// name is persisted. Stays raw (no hub dispatch): it sits on the
  /// per-attachment render path, where a snackbar per failed row would storm.
  Future<String> resolvePath(ShowcaseNoteAttachmentModel attachment) async {
    final dir = await _attachmentsDir();
    return '${dir.path}/${attachment.fileName}';
  }

  /// [1. Pick or capture photo] Camera capture or library pick. The kit
  /// returns a TEMP file — it is moved into the attachments dir or it would
  /// vanish with the cache. Permission denial, cancellation and missing
  /// hardware all collapse to null here (the UI already gates the camera via
  /// [isCameraAvailable]); a plugin/IO throw collapses to null too, via the
  /// AppBoxKitAction fallback, after an error snackbar.
  Future<ShowcaseNoteAttachmentModel?> pickPhoto({required bool fromCamera}) =>
      abxActionHub.send<ShowcaseNoteAttachmentModel?>(
        ShowcaseNotesMediaOp.pickPhoto.name,
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
        errorNotification: ShowcaseNotesMediaOp.pickPhoto.error,
        errorMessage: 'Photo capture failed',
        withValue: null,
      );

  /// [2. Record voice memo] False on permission denial (the view surfaces that
  /// — not an error, no snackbar); a recorder/plugin throw also collapses to
  /// false, after an error snackbar.
  Future<bool> startRecording() => abxActionHub.send<bool>(
        ShowcaseNotesMediaOp.startRecording.name,
        () async {
          if (!await _recorder.hasPermission()) return false;
          await _player.stop();
          playingAttachmentId$.add(null);

          final dir = await _attachmentsDir();
          // Encoder is aacLc → .m4a inside the kit, matching iOS voice memos.
          await _recorder.start(path: '${dir.path}/${_uuid.v4()}.m4a');
          return true;
        },
        errorNotification: ShowcaseNotesMediaOp.startRecording.error,
        errorMessage: 'Recording start failed',
        withValue: false,
      );

  /// [2. Record voice memo] Stops the in-progress recording and returns the
  /// voice memo model.
  Future<ShowcaseNoteAttachmentModel?> stopRecording() =>
      abxActionHub.send<ShowcaseNoteAttachmentModel?>(
        ShowcaseNotesMediaOp.stopRecording.name,
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
        errorNotification: ShowcaseNotesMediaOp.stopRecording.error,
        errorMessage: 'Recording stop failed',
        withValue: null,
      );

  /// [2. Record voice memo] Throws away the in-progress recording.
  Future<void> cancelRecording() => abxActionHub.send<void>(
        ShowcaseNotesMediaOp.cancelRecording.name,
        () => _recorder.cancel(),
        errorNotification: ShowcaseNotesMediaOp.cancelRecording.error,
        errorMessage: 'Recording cancel failed',
      );

  /// [3. Play back audio] Play [attachment] from the start, or toggle
  /// pause/resume when it is the one already loaded.
  Future<void> togglePlayback(ShowcaseNoteAttachmentModel attachment) =>
      abxActionHub.send<void>(
        '${ShowcaseNotesMediaOp.playback.name}.${attachment.id}',
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
        errorNotification: ShowcaseNotesMediaOp.playback.error,
        errorMessage: 'Playback failed',
      );

  /// [3. Play back audio] Stops the player and clears the loaded attachment.
  Future<void> stopPlayback() async {
    await _player.stop();
    playingAttachmentId$.add(null);
  }

  /// [4. Attachment files] Best-effort binary cleanup when an attachment is
  /// removed from a note.
  Future<void> deleteFile(ShowcaseNoteAttachmentModel attachment) =>
      abxActionHub.send<void>(
        '${ShowcaseNotesMediaOp.deleteFile.name}.${attachment.id}',
        () async {
          if (playingAttachmentId$.value == attachment.id) await stopPlayback();
          final file = File(await resolvePath(attachment));
          if (await file.exists()) await file.delete();
        },
        errorNotification: ShowcaseNotesMediaOp.deleteFile.error,
        errorMessage: 'Attachment cleanup failed',
      );

  // ── Cleanup ──────────────────────────────────────────────────────────────

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
