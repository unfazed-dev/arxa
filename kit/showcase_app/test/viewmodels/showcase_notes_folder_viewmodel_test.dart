import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart'
    show AppBoxKitErrorService, AppBoxKitNotificationService, BehaviorSubject;
import 'package:appbox_kit_ui_library/appbox_kit_testing.dart';
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:appbox_kit_showcase_app/enums/showcase_notes_enums/enums.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_viewmodel.dart';

import '../helpers/test_helpers.dart';

/// ShowcaseNotesFolderViewModel's behaviors over a mocked facade: scope
/// resolution (all/trash/folder), the live title lookup, the query$ → groups$
/// filter, and the mutation delegations. The facade's own semantics (iOS
/// grouping, trash unpinning, …) are covered in test/services/notes_facade_test.dart.
final _evan = AppBoxKitAuthSession(
  user: AppBoxKitAuthUser(id: 'user-1', email: 'evan@seed.local'),
);

ShowcaseNoteFolderModel _folder(String id, String name, int sortOrder) =>
    ShowcaseNoteFolderModel(
      id: id,
      name: name,
      sortOrder: sortOrder,
      owner: 'user-1',
      createdAt: DateTime.utc(2026, 7, 1),
    );

ShowcaseNoteModel _note(
  String id,
  String body, {
  bool pinned = false,
  bool deleted = false,
  String folderId = 'folder-work',
}) =>
    ShowcaseNoteModel(
      id: id,
      folderId: folderId,
      owner: 'user-1',
      body: body,
      pinned: pinned,
      deletedAt: deleted ? DateTime.utc(2026, 7, 9) : null,
      createdAt: DateTime.utc(2026, 7, 1),
      updatedAt: DateTime.utc(2026, 7, 2),
    );

void main() {
  // mocktail any() on model-typed port parameters.
  registerFallbackValue(_note('fallback', ''));

  group('ShowcaseNotesFolderViewModel', () {
    late MockShowcaseNotesFacadeService facade;

    setUp(() async {
      registerServices();
      registerAppBoxKitActionServices();
      // The real AppBoxKitAction error path logs through the error service's
      // late Talker — initialize it before any op can fail.
      await locator<AppBoxKitErrorService>().initialize();
      facade = getAndRegisterShowcaseNotesFacadeService();
    });
    tearDown(() => locator.reset());

    BehaviorSubject<AppBoxKitAuthSession?> stubSignedIn() {
      final session = seededSubject<AppBoxKitAuthSession?>(_evan);
      when(() => facade.session$).thenAnswer((_) => session.stream);
      return session;
    }

    test(
        'notes.folders.browse-the-notes-in-a-folder — notes\$ scopes to the folder\'s live notes',
        () async {
      // given
      stubSignedIn();
      when(() => facade.notesIn$('user-1', folderId: 'folder-work')).thenAnswer(
          (_) => Stream.value(
              [_note('n1', 'Standup notes'), _note('n2', 'Q2 retro')]));
      final vm = ShowcaseNotesFolderViewModel(folderKey: 'folder-work');
      addTearDown(vm.dispose);

      // when — subscribing is the act for a pass-through stream; the single
      // facade event is the whole sequence (no VM-owned seed to assert).
      final expectation = expectLater(
        vm.notes$,
        emitsInOrder([
          predicate<List<ShowcaseNoteModel>>((notes) =>
              notes.length == 2 &&
              notes.first.id == 'n1' &&
              notes.last.id == 'n2'),
        ]),
      );

      // then
      await expectation.timeout(const Duration(milliseconds: 500));
    });

    test(
        'notes.folders.browse-the-notes-in-a-folder — title\$ seeds the fallback, then emits the live folder name',
        () async {
      // given
      stubSignedIn();
      when(() => facade.folders$('user-1')).thenAnswer(
          (_) => Stream.value([_folder('folder-work', 'Work', 1)]));
      final vm = ShowcaseNotesFolderViewModel(folderKey: 'folder-work');
      addTearDown(vm.dispose);

      // when / then — full sequence including the startWith('Notes') seed, so
      // the app bar never flashes a loading state.
      await expectLater(vm.title$, emitsInOrder(['Notes', 'Work']))
          .timeout(const Duration(milliseconds: 500));
    });

    test('title\$ is fixed for the All Notes and Recently Deleted scopes',
        () async {
      // given / when / then — static scopes never touch the facade.
      final all = ShowcaseNotesFolderViewModel(folderKey: 'all');
      addTearDown(all.dispose);
      await expectLater(all.title$, emitsInOrder(['All Notes']))
          .timeout(const Duration(milliseconds: 500));

      final trash = ShowcaseNotesFolderViewModel(folderKey: 'trash');
      addTearDown(trash.dispose);
      await expectLater(trash.title$, emitsInOrder(['Recently Deleted']))
          .timeout(const Duration(milliseconds: 500));
    });

    test(
        'notes.folders.browse-the-notes-in-a-folder — the viewmodel parses '
        'folderKey into the sealed scope once', () {
      // given / when / then — sentinels map to their scope types (driving
      // isAll/isTrash), anything else is a folder scope.
      final all = ShowcaseNotesFolderViewModel(folderKey: 'all');
      addTearDown(all.dispose);
      expect(all.scope, isA<ShowcaseFolderScopeAll>());
      expect(all.isAll, isTrue);
      expect(all.isTrash, isFalse);

      final trash = ShowcaseNotesFolderViewModel(folderKey: 'trash');
      addTearDown(trash.dispose);
      expect(trash.scope, isA<ShowcaseFolderScopeTrash>());
      expect(trash.isTrash, isTrue);
      expect(trash.isAll, isFalse);

      final folder = ShowcaseNotesFolderViewModel(folderKey: 'folder-work');
      addTearDown(folder.dispose);
      expect(folder.scope, isA<ShowcaseFolderScopeFolder>());
      expect(folder.isAll, isFalse);
      expect(folder.isTrash, isFalse);
    });

    test(
        'search-and-attachments.search.search-notes-by-text — setQuery filters groups\$ to body matches',
        () async {
      // given
      stubSignedIn();
      when(() => facade.notesIn$('user-1', folderId: null)).thenAnswer(
        (_) => Stream.value([
          _note('n1', 'Groceries\nOat milk\nEspresso beans'),
          _note('n2', 'Q2 retro\nWhat went well'),
        ]),
      );
      final vm = ShowcaseNotesFolderViewModel(folderKey: 'all');
      addTearDown(vm.dispose);
      final expectation = expectLater(
        vm.groups$,
        emitsInOrder([
          // The seeded empty query emits the scope unfiltered first.
          predicate<List<ShowcaseNoteGroup>>(
              (groups) => groups.expand((g) => g.notes).length == 2),
          predicate<List<ShowcaseNoteGroup>>((groups) {
            final notes = groups.expand((g) => g.notes).toList();
            return notes.length == 1 && notes.single.id == 'n1';
          }),
        ]),
      );

      // when — flush first so the seeded (unfiltered) emission lands before
      // the query event; otherwise combineLatest coalesces straight to the
      // filtered list and there is no first emission to observe.
      await pumpEventQueue();
      vm.setQuery('ESPRESSO');

      // then — case-insensitive body match; full sequence asserted.
      await expectation.timeout(const Duration(milliseconds: 500));
    });

    test(
        'notes.pin-notes.pin-a-note-to-the-top-of-the-inbox — groups\$ leads with the Pinned section',
        () async {
      // given
      stubSignedIn();
      when(() => facade.notesIn$('user-1', folderId: null)).thenAnswer(
        (_) => Stream.value([
          _note('plain', 'Q2 retro'),
          _note('pinned', 'Groceries', pinned: true),
        ]),
      );
      final vm = ShowcaseNotesFolderViewModel(folderKey: 'all');
      addTearDown(vm.dispose);

      // when / then — the pinned note surfaces above every date section,
      // regardless of updatedAt.
      await expectLater(
        vm.groups$,
        emitsInOrder([
          predicate<List<ShowcaseNoteGroup>>((groups) =>
              groups.first.label == 'Pinned' &&
              groups.first.notes.single.id == 'pinned'),
        ]),
      ).timeout(const Duration(milliseconds: 500));
    });

    test(
        'notes.pin-notes.pin-a-note-to-the-top-of-the-inbox — togglePin sends the unpinned note to the facade',
        () async {
      // given
      final unpinned = _note('n1', 'Standup notes');
      when(() => facade.togglePin(any()))
          .thenAnswer((_) async => unpinned.copyWith(pinned: true));
      final vm = ShowcaseNotesFolderViewModel(folderKey: 'folder-work');
      addTearDown(vm.dispose);

      // when
      await vm.togglePin(unpinned);

      // then — trust boundary: the facade owns the pin mutation.
      verify(() => facade.togglePin(unpinned)).called(1);
    });

    test(
        'notes.pin-notes.unpin-a-pinned-note — togglePin sends the pinned note to the facade',
        () async {
      // given
      final pinned = _note('n1', 'Groceries', pinned: true);
      when(() => facade.togglePin(any()))
          .thenAnswer((_) async => pinned.copyWith(pinned: false));
      final vm = ShowcaseNotesFolderViewModel(folderKey: 'folder-work');
      addTearDown(vm.dispose);

      // when
      await vm.togglePin(pinned);

      // then — same facade op unpins; the facade flips the flag.
      verify(() => facade.togglePin(pinned)).called(1);
    });

    test('notes.trash-and-restore.trash-a-note — moveToTrash delegates to the facade',
        () async {
      // given
      final live = _note('n1', 'Q2 retro');
      when(() => facade.moveToTrash(any())).thenAnswer(
          (_) async => live.copyWith(deletedAt: () => DateTime.utc(2026, 7, 12)));
      final vm = ShowcaseNotesFolderViewModel(folderKey: 'folder-work');
      addTearDown(vm.dispose);

      // when
      await vm.moveToTrash(live);

      // then — trust boundary; the facade owns the iOS semantics (soft delete,
      // unpin on trash — covered in notes_facade_test).
      verify(() => facade.moveToTrash(live)).called(1);
    });

    test(
        'notes.trash-and-restore.restore-a-trashed-note — restore delegates to the facade',
        () async {
      // given
      final trashed = _note('n1', 'Old draft', deleted: true);
      when(() => facade.restore(any()))
          .thenAnswer((_) async => trashed.copyWith(deletedAt: () => null));
      final vm = ShowcaseNotesFolderViewModel(folderKey: 'trash');
      addTearDown(vm.dispose);

      // when
      await vm.restore(trashed);

      // then
      verify(() => facade.restore(trashed)).called(1);
    });

    test(
        'notes.note-crud.delete-a-note-forever — deletePermanently delegates to the facade',
        () async {
      // given
      final doomed = _note('n1', 'Old draft', deleted: true);
      when(() => facade.deletePermanently(any())).thenAnswer((_) async {});
      final vm = ShowcaseNotesFolderViewModel(folderKey: 'trash');
      addTearDown(vm.dispose);

      // when
      await vm.deletePermanently(doomed);

      // then — the confirmation lives in confirmDeletePermanently; the VM
      // delegates.
      verify(() => facade.deletePermanently(doomed)).called(1);
    });

    test(
        'notes.note-crud.delete-a-note-forever — confirmDeletePermanently deletes only when the user confirms',
        () async {
      // given
      final doomed = _note('n1', 'Old draft', deleted: true);
      when(() => facade.deletePermanently(any())).thenAnswer((_) async {});
      // The kit notification fake (registered by
      // registerAppBoxKitActionServices) scripts the confirm.
      final notifications = locator<AppBoxKitNotificationService>()
          as FakeAppBoxKitNotificationService;
      final vm = ShowcaseNotesFolderViewModel(folderKey: 'trash');
      addTearDown(vm.dispose);

      // when — the user cancels (default confirmResult is false)
      await vm.confirmDeletePermanently(doomed);

      // then — the facade never hears about it
      verifyNever(() => facade.deletePermanently(any()));

      // when — the user confirms
      notifications.confirmResult = true;
      await vm.confirmDeletePermanently(doomed);

      // then
      verify(() => facade.deletePermanently(doomed)).called(1);
    });

    test('emptyTrash passes the live session owner to the facade', () async {
      // given
      when(() => facade.currentSession).thenReturn(_evan);
      when(() => facade.emptyTrash(any())).thenAnswer((_) async {});
      final vm = ShowcaseNotesFolderViewModel(folderKey: 'trash');
      addTearDown(vm.dispose);

      // when
      await vm.emptyTrash();

      // then
      verify(() => facade.emptyTrash('user-1')).called(1);
    });

    test('emptyTrash is a no-op while signed out', () async {
      // given — currentSession unstubbed → null: the signed-out state.
      final vm = ShowcaseNotesFolderViewModel(folderKey: 'trash');
      addTearDown(vm.dispose);

      // when
      await vm.emptyTrash();

      // then — no owner, no purge.
      verifyNever(() => facade.emptyTrash(any()));
    });

    test('confirmEmptyTrash purges only when the user confirms', () async {
      // given
      when(() => facade.currentSession).thenReturn(_evan);
      when(() => facade.emptyTrash(any())).thenAnswer((_) async {});
      final notifications = locator<AppBoxKitNotificationService>()
          as FakeAppBoxKitNotificationService;
      final vm = ShowcaseNotesFolderViewModel(folderKey: 'trash');
      addTearDown(vm.dispose);

      // when — the user cancels (default confirmResult is false)
      await vm.confirmEmptyTrash();

      // then — no purge
      verifyNever(() => facade.emptyTrash(any()));

      // when — the user confirms
      notifications.confirmResult = true;
      await vm.confirmEmptyTrash();

      // then
      verify(() => facade.emptyTrash('user-1')).called(1);
    });

    test(
        'notes.note-crud.create-a-note — compose() in a folder scope creates the note there and returns its id',
        () async {
      // given
      when(() => facade.currentSession).thenReturn(_evan);
      when(() => facade.createNote('user-1', 'folder-work')).thenAnswer(
          (_) async => _note('note-new', '', folderId: 'folder-work'));
      final vm = ShowcaseNotesFolderViewModel(folderKey: 'folder-work');
      addTearDown(vm.dispose);

      // when
      final id = await vm.compose();

      // then — the caller navigates to the returned id.
      expect(id, 'note-new');
      verify(() => facade.createNote('user-1', 'folder-work')).called(1);
    });

    test(
        'notes.note-crud.create-a-note — compose() from All Notes files the new note in the first user folder',
        () async {
      // given — from 'all' / 'trash' there is no natural folder, so the
      // first user folder is the compose target. (Folder placement of an
      // existing note is the moveNoteToFolder op, cited on its own tests.)
      stubSignedIn();
      when(() => facade.currentSession).thenReturn(_evan);
      when(() => facade.folders$('user-1')).thenAnswer(
        (_) => Stream.value([
          _folder('folder-notes', 'Notes', 0),
          _folder('folder-work', 'Work', 1),
        ]),
      );
      when(() => facade.createNote('user-1', 'folder-notes')).thenAnswer(
          (_) async => _note('note-new', '', folderId: 'folder-notes'));
      final vm = ShowcaseNotesFolderViewModel(folderKey: 'all');
      addTearDown(vm.dispose);

      // when
      final id = await vm.compose();

      // then
      expect(id, 'note-new');
      verify(() => facade.createNote('user-1', 'folder-notes')).called(1);
    });

    test(
        'notes.folders.move-a-note-into-a-folder — moveNoteToFolder delegates to the facade',
        () async {
      // given
      final note = _note('n1', 'Q2 retro');
      when(() => facade.moveNoteToFolder(any(), any()))
          .thenAnswer((_) async => note.copyWith(folderId: 'folder-personal'));
      final vm = ShowcaseNotesFolderViewModel(folderKey: 'folder-work');
      addTearDown(vm.dispose);

      // when
      await vm.moveNoteToFolder(note, 'folder-personal');

      // then — trust boundary; the facade owns the move semantics (guards,
      // stream placement — covered in notes_facade_test).
      verify(() => facade.moveNoteToFolder(note, 'folder-personal')).called(1);
    });

    test('compose() returns null while signed out', () async {
      // given — currentSession unstubbed → null.
      final vm = ShowcaseNotesFolderViewModel(folderKey: 'folder-work');
      addTearDown(vm.dispose);

      // when / then — no owner: no note, no navigation target.
      expect(await vm.compose(), isNull);
      verifyNever(() => facade.createNote(any(), any()));
    });
  });
}
