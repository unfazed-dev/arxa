import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_media/arxa_kit_media.dart';
import 'package:arxa_kit_media/arxa_kit_testing.dart';
import 'package:arxa_kit_showcase_app/app/app.locator.dart';
import 'package:arxa_kit_showcase_app/data/models/showcase_notes_models/showcase_note_attachment_model.dart';
import 'package:arxa_kit_showcase_app/enums/showcase_notes_enums/enums.dart';
import 'package:arxa_kit_showcase_app/services/showcase_notes_services/adapters/showcase_notes_media_adapter_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  ShowcaseNoteAttachmentModel memo(String id) => ShowcaseNoteAttachmentModel(
        id: id,
        kind: ShowcaseNoteAttachmentKind.audio,
        fileName: '$id.m4a',
        durationMs: 1000,
        createdAt: DateTime.utc(2026, 1, 1),
      );

  group('ShowcaseNotesMediaAdapterServiceTest -', () {
    late Directory docsDir;
    late FakeArxaKitMediaCaptureService capture;
    late FakeArxaKitAudioRecorderService recorder;
    late FakeArxaKitAudioPlayerService player;
    late ShowcaseNotesMediaAdapterService adapter;

    setUp(() {
      registerServices();
      registerArxaKitActionServices();
      // The adapter resolves real paths through path_provider's platform
      // channel; point it at a throwaway temp dir.
      docsDir = Directory.systemTemp.createTempSync('notes_media_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
        return call.method == 'getApplicationDocumentsDirectory'
            ? docsDir.path
            : null;
      });
      capture = FakeArxaKitMediaCaptureService();
      recorder = FakeArxaKitAudioRecorderService();
      player = FakeArxaKitAudioPlayerService();
      adapter = ShowcaseNotesMediaAdapterService(
        capture: capture,
        recorder: recorder,
        player: player,
      );
    });

    tearDown(() async {
      await adapter.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
      if (docsDir.existsSync()) docsDir.deleteSync(recursive: true);
      await locator.reset();
    });

    test(
        'search-and-attachments.media-attachments.attach-a-photo-to-a-note — a camera capture is stored in the attachments dir as a photo attachment',
        () async {
      // given — camera hardware present
      expect(adapter.isCameraAvailable, isTrue);

      // when
      final photo = await adapter.pickPhoto(fromCamera: true);

      // then — the camera source was used and the temp capture was moved into
      // the app's attachments dir under the row's fileName
      expect(capture.requestedSources, [ArxaKitMediaSource.camera]);
      expect(photo, isNotNull);
      expect(photo!.kind, ShowcaseNoteAttachmentKind.photo);
      expect(photo.fileName, endsWith('.jpg'));
      final stored = File(
          '${docsDir.path}/arxa_kit_showcase_app/attachments/${photo.fileName}');
      expect(stored.existsSync(), isTrue);
    });

    test(
        'search-and-attachments.media-attachments.attach-a-photo-to-a-note — a camera request degrades to the gallery where no camera exists',
        () async {
      // given — the simulator case: no camera hardware
      capture.hasCamera = false;
      expect(adapter.isCameraAvailable, isFalse);

      // when
      final photo = await adapter.pickPhoto(fromCamera: true);

      // then — gallery picked instead of crashing; the note still gets a photo
      expect(capture.requestedSources, [ArxaKitMediaSource.gallery]);
      expect(photo, isNotNull);
      expect(photo!.kind, ShowcaseNoteAttachmentKind.photo);
    });

    test(
        'search-and-attachments.media-attachments.attach-an-audio-recording-to-a-note — starting a recording stops whatever is playing and returns true',
        () async {
      // given — a voice memo is playing
      await adapter.togglePlayback(memo('a1'));
      await pumpEventQueue();
      expect(adapter.playingAttachmentId$.value, 'a1');
      final stopped = expectLater(
        adapter.playingAttachmentId$,
        emitsInOrder(['a1', isNull]),
      );

      // when
      final started = await adapter.startRecording();

      // then — playback stopped, recorder capturing into the attachments dir
      expect(started, isTrue);
      await stopped.timeout(const Duration(milliseconds: 500));
      expect(player.isPlaying, isFalse);
      expect(recorder.isRecording, isTrue);
      expect(
        recorder.startedPaths.single,
        allOf(
            contains('arxa_kit_showcase_app/attachments/'), endsWith('.m4a')),
      );
    });

    test(
        'search-and-attachments.media-attachments.attach-an-audio-recording-to-a-note — a permission denial returns false and starts nothing',
        () async {
      // given
      recorder.permission = false;

      // when
      final started = await adapter.startRecording();

      // then — denial is a plain false (the view surfaces it), not an error
      expect(started, isFalse);
      expect(recorder.isRecording, isFalse);
      expect(recorder.startedPaths, isEmpty);
    });

    test(
        'search-and-attachments.media-attachments.attach-an-audio-recording-to-a-note — stopping a recording yields an audio attachment carrying the recorded file and duration',
        () async {
      // given — a 7-second recording in flight
      await adapter.startRecording();
      recorder.driveElapsed(const Duration(seconds: 7));

      // when
      final memoAttachment = await adapter.stopRecording();

      // then — the row points at the recorded file with its length
      expect(memoAttachment, isNotNull);
      expect(memoAttachment!.kind, ShowcaseNoteAttachmentKind.audio);
      expect(memoAttachment.durationMs, 7000);
      final recordedPath = recorder.startedPaths.single!;
      expect(
        memoAttachment.fileName,
        recordedPath.substring(recordedPath.lastIndexOf('/') + 1),
        reason: 'rows carry only the file NAME; resolvePath re-derives the dir',
      );
    });

    test(
        'search-and-attachments.media-attachments.play-back-an-audio-attachment — toggling the loaded attachment pauses, then resumes it',
        () async {
      // given — a1 loaded and playing
      await adapter.togglePlayback(memo('a1'));
      await pumpEventQueue();
      final states = expectLater(
        adapter.playerState$,
        emitsInOrder([
          predicate<ArxaKitPlaybackState>((s) => s.playing),
          predicate<ArxaKitPlaybackState>((s) => !s.playing),
          predicate<ArxaKitPlaybackState>((s) => s.playing),
        ]),
      );

      // when — same attachment toggled twice
      await adapter.togglePlayback(memo('a1'));
      await adapter.togglePlayback(memo('a1'));

      // then — pause then resume, and the attachment stays loaded throughout
      await states.timeout(const Duration(milliseconds: 500));
      expect(adapter.playingAttachmentId$.value, 'a1');
      expect(player.loadedPaths, hasLength(1),
          reason: 'same-id toggles never reload the file');
    });

    test(
        'search-and-attachments.media-attachments.play-back-an-audio-attachment — toggling a different attachment switches the player to it',
        () async {
      // given — a1 playing
      await adapter.togglePlayback(memo('a1'));
      await pumpEventQueue();
      final switched = expectLater(
        adapter.playingAttachmentId$,
        emitsInOrder(['a1', 'a2']),
      );

      // when
      await adapter.togglePlayback(memo('a2'));

      // then — the new memo is loaded and playing
      await switched.timeout(const Duration(milliseconds: 500));
      expect(player.loadedPaths.last, endsWith('a2.m4a'));
      expect(player.isPlaying, isTrue);
    });

    test(
        'search-and-attachments.media-attachments.play-back-an-audio-attachment — deleting the playing attachment stops playback and removes its file',
        () async {
      // given — a1 playing, its binary on disk
      await adapter.togglePlayback(memo('a1'));
      await pumpEventQueue();
      final file = File(await adapter.resolvePath(memo('a1')));
      await file.create(recursive: true);
      final stopped = expectLater(
        adapter.playingAttachmentId$,
        emitsInOrder(['a1', isNull]),
      );

      // when
      await adapter.deleteFile(memo('a1'));

      // then — playback stopped first, then the binary removed
      await stopped.timeout(const Duration(milliseconds: 500));
      expect(player.isPlaying, isFalse);
      expect(file.existsSync(), isFalse);
    });

    test(
        'search-and-attachments.media-attachments.play-back-an-audio-attachment — isAttachmentPlaying\$ is true only for the loaded, playing attachment',
        () async {
      // given
      final states = <bool>[];
      final sub = adapter.isAttachmentPlaying$('v1').listen(states.add);
      addTearDown(sub.cancel);
      await pumpEventQueue(); // seed: idle, nothing loaded

      // when — playing with nothing loaded, then loaded AND playing
      player.driveState(const ArxaKitPlaybackState(
        playing: true,
        processing: ArxaKitMediaProcessingState.ready,
      ));
      adapter.playingAttachmentId$.add('v1');
      await pumpEventQueue();

      // then — true only when both hold
      expect(states, [false, false, true]);
    });

    test(
        'search-and-attachments.media-attachments.play-back-an-audio-attachment — playbackProgress\$ pairs the live position with the track length',
        () async {
      // given
      final progress = <ArxaKitPlaybackProgress>[];
      final sub = adapter.playbackProgress$.listen(progress.add);
      addTearDown(sub.cancel);
      await pumpEventQueue(); // seed: zero position, unknown length

      // when — the player reports a position tick, then the track length
      player.drivePosition(const Duration(seconds: 3));
      player.driveDuration(const Duration(seconds: 10));
      await pumpEventQueue();

      // then
      expect(progress, [
        (position: Duration.zero, duration: null),
        (position: const Duration(seconds: 3), duration: null),
        (
          position: const Duration(seconds: 3),
          duration: const Duration(seconds: 10),
        ),
      ]);
    });
  });
}
