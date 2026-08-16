import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:appbox_kit_media/appbox_kit_media.dart'
    show AppBoxKitPlaybackProgress;
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_ui_library/appbox_kit_testing.dart';
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:appbox_kit_showcase_app/enums/showcase_notes_enums/enums.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart';

import '../helpers/test_helpers.dart';

class _FakeNote extends Fake implements ShowcaseNoteModel {}

class _FakeAttachment extends Fake implements ShowcaseNoteAttachmentModel {}

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

    setUpAll(() {
      registerFallbackValue(_FakeNote());
      registerFallbackValue(_FakeAttachment());
    });

    setUp(() {
      registerServices();
      registerAppBoxKitActionServices();
      // The mocks register under their real service types; re-running the
      // factories captures typed handles (each re-registers a fresh mock).
      notes = getAndRegisterShowcaseNotesFacadeService();
    });

    tearDown(() {
      locator.reset();
    });

    /// Stubs `notes.note$` with [subject] (seed it before constructing the VM)
    /// and returns the VM with its side-effect watch flushed.
    Future<ShowcaseNoteEditorViewModel> openEditor(
      BehaviorSubject<ShowcaseNoteModel?> subject, {
      ShowcaseQuickAction? quickAction,
    }) async {
      when(() => notes.note$('n1')).thenAnswer((_) => subject.stream);
      final vm =
          ShowcaseNoteEditorViewModel(noteId: 'n1', quickAction: quickAction);
      addTearDown(vm.dispose);
      await pumpEventQueue(); // deliver the seeded note to the watch callback
      return vm;
    }

    test(
        'notes.note-crud.edit-a-note — body seeds once from the loaded note and later note\$ emits never clobber what the user typed',
        () async {
      // given
      final subject =
          seededSubject<ShowcaseNoteModel?>(note(body: 'seed body'));
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
      expect(vm.body, 'seed body',
          reason: 'seeded once from the first note\$ emit');
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
        'notes.trash-and-restore.trash-a-note — deleting the open note drops it from the editor stream',
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
      // given — the facade owns pick→attach; the mock replays its outcome
      final photo = attachment(id: 'p1');
      final subject = seededSubject<ShowcaseNoteModel?>(note());
      when(() => notes.addPhoto(any(), fromCamera: any(named: 'fromCamera')))
          .thenAnswer((_) async {
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
        'search-and-attachments.media-attachments.attach-a-photo-to-a-note — the route\'s camera quick action auto-captures once on first load and never re-runs',
        () async {
      // given — the route carried `?quickAction=camera` (Folders "New Photo")
      final photo = attachment(id: 'p1');
      final subject = seededSubject<ShowcaseNoteModel?>(note());
      when(() => notes.isCameraAvailable).thenReturn(true);
      final added = <ShowcaseNoteModel>[];
      when(() => notes.addPhoto(any(), fromCamera: any(named: 'fromCamera')))
          .thenAnswer((invocation) async {
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
      await openEditor(subject, quickAction: ShowcaseQuickAction.camera);

      // then — the photo attached exactly once
      await captured.timeout(const Duration(milliseconds: 500));

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
      when(() => notes.startRecording()).thenAnswer((_) async => false);
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
      when(() => notes.addVoiceNote(any())).thenAnswer((_) async {
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
        'search-and-attachments.media-attachments.play-back-an-audio-attachment — isAttachmentPlaying\$ forwards the facade\'s per-attachment playing stream',
        () async {
      // given
      final memo = attachment(id: 'v1', kind: ShowcaseNoteAttachmentKind.audio);
      final playing = seededSubject<bool>(false);
      when(() => notes.isAttachmentPlaying$('v1'))
          .thenAnswer((_) => playing.stream);
      when(() => notes.togglePlayback(any())).thenAnswer((_) async {
        playing.add(true);
      });
      final subject =
          seededSubject<ShowcaseNoteModel?>(note(attachments: [memo]));
      final vm = await openEditor(subject);
      final sequence = expectLater(
        vm.isAttachmentPlaying$('v1'),
        emitsInOrder([isFalse, isTrue]),
      );

      // when
      await vm.togglePlayback(memo);

      // then
      await sequence.timeout(const Duration(milliseconds: 500));
    });

    test(
        'search-and-attachments.media-attachments.attach-a-photo-to-a-note — removing an attachment asks first: only a confirmed dialog calls the facade',
        () async {
      // given
      final photo = attachment(id: 'p1');
      final subject =
          seededSubject<ShowcaseNoteModel?>(note(attachments: [photo]));
      // The kit notification fake (registered by registerAppBoxKitActionServices)
      // scripts the confirm: cancel first, accept second.
      final notifications = locator<AppBoxKitNotificationService>()
          as FakeAppBoxKitNotificationService;
      when(() => notes.removeAttachment(any(), any()))
          .thenAnswer((_) async => note());
      final vm = await openEditor(subject);

      // when — the user cancels the confirmation
      await vm.confirmRemoveAttachment(photo);

      // then — the facade never hears about it
      verifyNever(() => notes.removeAttachment(any(), any()));

      // when — the user confirms
      notifications.confirmResult = true;
      await vm.confirmRemoveAttachment(photo);

      // then — one facade call carrying the note and the attachment (the
      // facade owns the unlink-then-delete-file ordering; tested there)
      verify(() => notes.removeAttachment(any(), photo)).called(1);
    });

    test(
        'search-and-attachments.media-attachments.play-back-an-audio-attachment — playbackProgress\$ forwards the facade\'s position/length pairing',
        () async {
      // given
      final progress = seededSubject<AppBoxKitPlaybackProgress>(
          (position: Duration.zero, duration: null));
      when(() => notes.playbackProgress$).thenAnswer((_) => progress.stream);
      final subject = seededSubject<ShowcaseNoteModel?>(note());
      final vm = await openEditor(subject);
      final sequence = expectLater(
        vm.playbackProgress$,
        emitsInOrder([
          equals((position: Duration.zero, duration: null)),
          equals((
            position: const Duration(seconds: 3),
            duration: const Duration(seconds: 10),
          )),
        ]),
      );

      // when — the player reports a tick with the track length known
      progress.add((
        position: const Duration(seconds: 3),
        duration: const Duration(seconds: 10),
      ));

      // then
      await sequence.timeout(const Duration(milliseconds: 500));
    });
  });
}
