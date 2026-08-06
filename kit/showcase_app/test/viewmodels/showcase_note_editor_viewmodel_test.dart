import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rxdart/rxdart.dart';
import 'package:appbox_kit_media/appbox_kit_media.dart'
    show AppBoxKitMediaProcessingState, AppBoxKitPlaybackState;
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart';

import '../helpers/test_helpers.dart';

class _FakeNote extends Fake implements ShowcaseNoteModel {}

class _FakeAttachment extends Fake implements ShowcaseNoteAttachmentModel {}

// The harness's bottom-sheet stub matches on `barrierColor` (Color) — mocktail
// needs a fallback registered before registerServices() runs.
class _FakeColor extends Fake implements Color {}

void main() {
  ShowcaseNoteModel note({
    String id = 'n1',
    String body = 'seed body',
    List<ShowcaseNoteAttachmentModel> attachments = const [],
  }) =>
      ShowcaseNoteModel(
        id: id,
        folderId: 'f1',
        owner: 'o1',
        body: body,
        attachments: attachments,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

  ShowcaseNoteAttachmentModel attachment({
    String id = 'a1',
    ShowcaseNoteAttachmentKind kind = ShowcaseNoteAttachmentKind.photo,
    int? durationMs,
  }) =>
      ShowcaseNoteAttachmentModel(
        id: id,
        kind: kind,
        fileName: '$id.bin',
        durationMs: durationMs,
        createdAt: DateTime.utc(2026, 1, 1),
      );

  group('ShowcaseNoteEditorViewModel Tests -', () {
    late MockShowcaseNotesFacadeService notes;
    late MockShowcaseNotesMediaAdapterService media;

    setUpAll(() {
      registerFallbackValue(_FakeNote());
      registerFallbackValue(_FakeAttachment());
      registerFallbackValue(_FakeColor());
    });

    setUp(() {
      registerServices();
      registerAppBoxKitActionServices();
      // The mocks register under their real service types; re-running the
      // factories captures typed handles (each re-registers a fresh mock).
      notes = getAndRegisterShowcaseNotesFacadeService();
      media = getAndRegisterShowcaseNotesMediaAdapterService();
      ShowcaseNoteEditorViewModel.pendingAction = null;
    });

    tearDown(() {
      ShowcaseNoteEditorViewModel.pendingAction = null;
      locator.reset();
    });

    /// Stubs `notes.note$` with [subject] (seed it before constructing the VM)
    /// and returns the VM with its side-effect watch flushed.
    Future<ShowcaseNoteEditorViewModel> openEditor(
      BehaviorSubject<ShowcaseNoteModel?> subject,
    ) async {
      when(() => notes.note$('n1')).thenAnswer((_) => subject.stream);
      final vm = ShowcaseNoteEditorViewModel(noteId: 'n1');
      addTearDown(vm.dispose);
      await pumpEventQueue(); // deliver the seeded note to the watch callback
      return vm;
    }

    test(
        'notes.note-crud.edit-a-note — body seeds once from the loaded note and later note\$ emits never clobber what the user typed',
        () async {
      // given
      final subject = seededSubject<ShowcaseNoteModel?>(note(body: 'seed body'));
      // Autosave made observable: the mock records every saved body so the test
      // can wait on the debounced write instead of a wall clock.
      final saves = StreamController<String>();
      addTearDown(saves.close);
      when(() => notes.saveBody(any(), any())).thenAnswer((invocation) async {
        final body = invocation.positionalArguments[1] as String;
        saves.add(body);
        return note(body: body);
      });
      final vm = await openEditor(subject);
      expect(vm.body, 'seed body', reason: 'seeded once from the first note\$ emit');
      final save = expectLater(saves.stream, emits('typed draft'));

      // when — the user types, then a write-back emit arrives before the
      // debounced save lands
      vm.onBodyChanged('typed draft');
      subject.add(note(body: 'server write-back'));
      await pumpEventQueue();

      // then — the typed text survives both the emit and the save round-trip
      await save.timeout(const Duration(seconds: 2));
      expect(vm.body, 'typed draft');
    });

    test(
        'notes.note-crud.edit-a-note — rapid body edits coalesce into one debounced autosave carrying the final text',
        () async {
      // given
      final subject = seededSubject<ShowcaseNoteModel?>(note());
      final saves = StreamController<String>();
      addTearDown(saves.close);
      when(() => notes.saveBody(any(), any())).thenAnswer((invocation) async {
        saves.add(invocation.positionalArguments[1] as String);
        return note();
      });
      final vm = await openEditor(subject);
      final save = expectLater(saves.stream, emitsInOrder(['third']));

      // when — three keystrokes inside the 500 ms debounce window
      vm
        ..onBodyChanged('first')
        ..onBodyChanged('second')
        ..onBodyChanged('third');

      // then — only the last edit is ever written (debounce outlasts 500 ms,
      // so the expectation gets a wider window than the stream-rule default)
      await save.timeout(const Duration(seconds: 2));
      verify(() => notes.saveBody(any(), any())).called(1);
    });

    test(
        'notes.note-crud.delete-a-note-forever — deleting the open note drops it from the editor stream',
        () async {
      // given
      final loaded = note();
      final subject = seededSubject<ShowcaseNoteModel?>(loaded);
      // The facade owns the row; the mock replays its outcome — the note is
      // gone — onto the same stream the editor binds.
      when(() => notes.moveToTrash(any())).thenAnswer((_) async {
        subject.add(null);
        return loaded;
      });
      final vm = await openEditor(subject);
      final gone = expectLater(vm.note$, emitsInOrder([isNotNull, isNull]));

      // when
      await vm.delete();

      // then
      await gone.timeout(const Duration(milliseconds: 500));
    });

    test(
        'search-and-attachments.media-attachments.attach-a-photo-to-a-note — a picked photo lands on the note as a photo attachment',
        () async {
      // given
      final photo = attachment(id: 'p1');
      final subject = seededSubject<ShowcaseNoteModel?>(note());
      when(() => media.pickPhoto(fromCamera: any(named: 'fromCamera')))
          .thenAnswer((_) async => photo);
      when(() => notes.addAttachment(any(), any())).thenAnswer((_) async {
        final withPhoto = note(attachments: [photo]);
        subject.add(withPhoto);
        return withPhoto;
      });
      final vm = await openEditor(subject);
      final attached = expectLater(
        vm.note$,
        emitsInOrder([
          predicate<ShowcaseNoteModel?>((n) => n!.attachments.isEmpty),
          predicate<ShowcaseNoteModel?>((n) =>
              n!.attachments.single.id == 'p1' &&
              n.attachments.single.kind == ShowcaseNoteAttachmentKind.photo),
        ]),
      );

      // when
      await vm.addPhoto(fromCamera: false);

      // then
      await attached.timeout(const Duration(milliseconds: 500));
    });

    test(
        'search-and-attachments.media-attachments.attach-a-photo-to-a-note — the pending camera intent auto-captures once on first load and consumes the slot',
        () async {
      // given — the Folders FAB queued "New Photo" before navigating here
      ShowcaseNoteEditorViewModel.pendingAction = 'camera';
      final photo = attachment(id: 'p1');
      final subject = seededSubject<ShowcaseNoteModel?>(note());
      when(() => media.isCameraAvailable).thenReturn(true);
      when(() => media.pickPhoto(fromCamera: any(named: 'fromCamera')))
          .thenAnswer((_) async => photo);
      final added = <ShowcaseNoteModel>[];
      when(() => notes.addAttachment(any(), any())).thenAnswer((invocation) async {
        added.add(invocation.positionalArguments[0] as ShowcaseNoteModel);
        final withPhoto = note(attachments: [photo]);
        subject.add(withPhoto);
        return withPhoto;
      });
      final captured = expectLater(
        subject.stream.map((n) => n?.attachments ?? const []),
        emitsInOrder([isEmpty, hasLength(1)]),
      );

      // when — the editor opens (the intent fires off the first note\$ emit)
      await openEditor(subject);

      // then — the photo attached, and the slot was consumed
      await captured.timeout(const Duration(milliseconds: 500));
      expect(ShowcaseNoteEditorViewModel.pendingAction, isNull);

      // and — a later note\$ emit does not re-run the intent
      subject.add(note(attachments: [photo]));
      await pumpEventQueue();
      expect(added, hasLength(1));
    });

    test(
        'search-and-attachments.media-attachments.attach-an-audio-recording-to-a-note — startRecording surfaces a permission denial as false',
        () async {
      // given
      final subject = seededSubject<ShowcaseNoteModel?>(note());
      when(() => media.startRecording()).thenAnswer((_) async => false);
      final vm = await openEditor(subject);

      // when / then — the view shows the denial; nothing else happens
      expect(await vm.startRecording(), isFalse);
    });

    test(
        'search-and-attachments.media-attachments.attach-an-audio-recording-to-a-note — a stopped recording lands on the note as an audio attachment with its duration',
        () async {
      // given
      final memo = attachment(
        id: 'v1',
        kind: ShowcaseNoteAttachmentKind.audio,
        durationMs: 7000,
      );
      final subject = seededSubject<ShowcaseNoteModel?>(note());
      when(() => media.stopRecording()).thenAnswer((_) async => memo);
      when(() => notes.addAttachment(any(), any())).thenAnswer((_) async {
        final withMemo = note(attachments: [memo]);
        subject.add(withMemo);
        return withMemo;
      });
      final vm = await openEditor(subject);
      final attached = expectLater(
        vm.note$,
        emitsInOrder([
          predicate<ShowcaseNoteModel?>((n) => n!.attachments.isEmpty),
          predicate<ShowcaseNoteModel?>((n) =>
              n!.attachments.single.id == 'v1' &&
              n.attachments.single.kind == ShowcaseNoteAttachmentKind.audio &&
              n.attachments.single.durationMs == 7000),
        ]),
      );

      // when
      await vm.stopRecording();

      // then
      await attached.timeout(const Duration(milliseconds: 500));
    });

    test(
        'search-and-attachments.media-attachments.play-back-an-audio-attachment — isAttachmentPlaying\$ turns true only for the loaded, playing attachment',
        () async {
      // given
      final memo = attachment(id: 'v1', kind: ShowcaseNoteAttachmentKind.audio);
      final playingId = seededSubject<String?>(null);
      final state = seededSubject<AppBoxKitPlaybackState>(AppBoxKitPlaybackState.idle);
      when(() => media.playingAttachmentId$).thenAnswer((_) => playingId);
      when(() => media.playerState$).thenAnswer((_) => state);
      when(() => media.togglePlayback(any())).thenAnswer((_) async {
        state.add(const AppBoxKitPlaybackState(
          playing: true,
          processing: AppBoxKitMediaProcessingState.ready,
        ));
        playingId.add('v1');
      });
      final subject = seededSubject<ShowcaseNoteModel?>(note(attachments: [memo]));
      final vm = await openEditor(subject);
      // Full sequence including the seed: idle (nothing loaded), still false
      // once playing but not yet loaded, true only when BOTH hold.
      final playing = expectLater(
        vm.isAttachmentPlaying$('v1'),
        emitsInOrder([isFalse, isFalse, isTrue]),
      );

      // when
      await vm.togglePlayback(memo);

      // then
      await playing.timeout(const Duration(milliseconds: 500));
    });

    test(
        'search-and-attachments.media-attachments.play-back-an-audio-attachment — playbackProgress\$ pairs the live position with the track length',
        () async {
      // given
      final position = seededSubject<Duration>(Duration.zero);
      final duration = seededSubject<Duration?>(null);
      when(() => media.position$).thenAnswer((_) => position);
      when(() => media.duration$).thenAnswer((_) => duration);
      final subject = seededSubject<ShowcaseNoteModel?>(note());
      final vm = await openEditor(subject);
      final progress = expectLater(
        vm.playbackProgress$,
        emitsInOrder([
          equals((position: Duration.zero, duration: null)),
          equals((position: const Duration(seconds: 3), duration: null)),
          equals((
            position: const Duration(seconds: 3),
            duration: const Duration(seconds: 10),
          )),
        ]),
      );

      // when — the player reports a position tick, then the track length
      position.add(const Duration(seconds: 3));
      duration.add(const Duration(seconds: 10));

      // then
      await progress.timeout(const Duration(milliseconds: 500));
    });
  });
}
