import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart'
    show AppBoxKitErrorService, AppBoxKitNotificationService, BehaviorSubject;
import 'package:appbox_kit_ui_library/appbox_kit_testing.dart';
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_viewmodel.dart';

import '../helpers/test_helpers.dart';

/// ShowcaseNotesViewModel's OWN behaviors — the session → overview/admin
/// switchMap cascade is covered by test/notes_viewmodel_test.dart over the real
/// facade; here the facade is mocked and only the VM's logic is pinned:
/// the create-account panel toggle/reset and the folder-op guards.
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

void main() {
  // mocktail any() on model-typed port parameters.
  registerFallbackValue(_folder('fallback', 'Fallback', 0));

  group('ShowcaseNotesViewModel', () {
    late MockShowcaseNotesFacadeService facade;
    late BehaviorSubject<AppBoxKitAuthSession?> session;

    setUp(() async {
      registerServices();
      registerAppBoxKitActionServices();
      // The real AppBoxKitAction error path logs through the error service's
      // late Talker — initialize it before any op can fail.
      await locator<AppBoxKitErrorService>().initialize();
      facade = getAndRegisterShowcaseNotesFacadeService();
      // Signed out by default; the VM's ctor watch subscribes to session$ on
      // construction, so the stub must exist before any VM is created.
      session = seededSubject<AppBoxKitAuthSession?>(null);
      when(() => facade.session$).thenAnswer((_) => session.stream);
    });
    tearDown(() => locator.reset());

    test('the create-account panel opens and closes on demand', () async {
      // given
      final vm = ShowcaseNotesViewModel();
      addTearDown(vm.dispose);
      final expectation = expectLater(
        vm.showCreateAccount$,
        emitsInOrder([isFalse, isTrue, isFalse]),
      );

      // when
      vm.openCreateAccount();
      vm.closeCreateAccount();

      // then — full sequence including the seeded false (canon streams rules).
      await expectation.timeout(const Duration(milliseconds: 500));
    });

    test('a session appearing resets the create-account panel to sign-in',
        () async {
      // given
      final vm = ShowcaseNotesViewModel();
      addTearDown(vm.dispose);
      final expectation = expectLater(
        vm.showCreateAccount$,
        emitsInOrder([isFalse, isTrue, isFalse]),
      );

      // when — the panel is open, then a sign-in lands on session$.
      vm.openCreateAccount();
      session.add(_evan);

      // then — watch('session.resetPanel') flips the panel back itself, so
      // signing in from either panel always swaps back cleanly.
      await expectation.timeout(const Duration(milliseconds: 500));
    });

    test(
        'notes.folders.create-a-folder — createFolder trims the name and sets sortOrder after the existing folders',
        () async {
      // given
      when(() => facade.currentSession).thenReturn(_evan);
      when(() => facade.overview$('user-1')).thenAnswer(
        (_) => Stream.value(
          ShowcaseNotesOverview(
            folders: [_folder('f1', 'Notes', 0), _folder('f2', 'Work', 1)],
            liveCountByFolder: const {},
            allCount: 4,
            trashCount: 0,
          ),
        ),
      );
      when(() => facade.createFolder(any(), any(),
              sortOrder: any(named: 'sortOrder')))
          .thenAnswer((i) async =>
              _folder('f3', i.positionalArguments[1] as String, 2));
      final vm = ShowcaseNotesViewModel();
      addTearDown(vm.dispose);

      // when
      await vm.createFolder('  Errands ');

      // then — trust boundary: the facade owns the write; the VM owns the
      // trim and the append-at-end sortOrder (2 existing folders → sortOrder 2).
      verify(() => facade.createFolder('user-1', 'Errands', sortOrder: 2))
          .called(1);
    });

    test('notes.folders.create-a-folder — a blank name is dropped before the facade',
        () async {
      // given
      when(() => facade.currentSession).thenReturn(_evan);
      final vm = ShowcaseNotesViewModel();
      addTearDown(vm.dispose);

      // when
      await vm.createFolder('   ');

      // then — the trim guard: no name, no write.
      verifyNever(() => facade.createFolder(any(), any(),
          sortOrder: any(named: 'sortOrder')));
    });

    test('notes.folders.create-a-folder — signed out, createFolder is a no-op',
        () async {
      // given — currentSession unstubbed: mocktail returns null for the
      // nullable getter, which is exactly the signed-out state.
      final vm = ShowcaseNotesViewModel();
      addTearDown(vm.dispose);

      // when
      await vm.createFolder('Errands');

      // then — no owner, no write.
      verifyNever(() => facade.createFolder(any(), any(),
          sortOrder: any(named: 'sortOrder')));
    });

    test('renameFolder trims and delegates to the facade', () async {
      // given
      final work = _folder('f2', 'Work', 1);
      when(() => facade.renameFolder(any(), any()))
          .thenAnswer((_) async => work);
      final vm = ShowcaseNotesViewModel();
      addTearDown(vm.dispose);

      // when
      await vm.renameFolder(work, '  Jobs ');

      // then — same trim guard as create.
      verify(() => facade.renameFolder(work, 'Jobs')).called(1);
    });

    test('renameFolder drops a blank name before the facade', () async {
      // given
      final work = _folder('f2', 'Work', 1);
      final vm = ShowcaseNotesViewModel();
      addTearDown(vm.dispose);

      // when
      await vm.renameFolder(work, '   ');

      // then
      verifyNever(() => facade.renameFolder(any(), any()));
    });

    test('deleteFolder delegates to the facade', () async {
      // given
      final work = _folder('f2', 'Work', 1);
      when(() => facade.deleteFolder(any())).thenAnswer((_) async {});
      final vm = ShowcaseNotesViewModel();
      addTearDown(vm.dispose);

      // when
      await vm.deleteFolder(work);

      // then — no VM-side guard here; the facade owns the iOS semantics
      // (live notes go to Recently Deleted — covered in notes_facade_test).
      verify(() => facade.deleteFolder(work)).called(1);
    });

    test(
        'notes.folders.create-a-folder — createFolderWithPrompt creates the folder only when the prompt returns a name',
        () async {
      // given
      when(() => facade.currentSession).thenReturn(_evan);
      when(() => facade.overview$('user-1')).thenAnswer(
        (_) => Stream.value(
          ShowcaseNotesOverview(
            folders: const [],
            liveCountByFolder: const {},
            allCount: 0,
            trashCount: 0,
          ),
        ),
      );
      when(() => facade.createFolder(any(), any(),
              sortOrder: any(named: 'sortOrder')))
          .thenAnswer(
              (i) async => _folder('f9', i.positionalArguments[1] as String, 0));
      // The kit notification fake (registered by
      // registerAppBoxKitActionServices) scripts the prompt.
      final notifications = locator<AppBoxKitNotificationService>()
          as FakeAppBoxKitNotificationService;
      final vm = ShowcaseNotesViewModel();
      addTearDown(vm.dispose);

      // when — the user cancels the prompt (default promptResult is null)
      await vm.createFolderWithPrompt();

      // then — no name, no write
      verifyNever(() => facade.createFolder(any(), any(),
          sortOrder: any(named: 'sortOrder')));

      // when — the user enters a name
      notifications.promptResult = 'Errands';
      await vm.createFolderWithPrompt();

      // then — one facade call (empty folder list → sortOrder 0)
      verify(() => facade.createFolder('user-1', 'Errands', sortOrder: 0))
          .called(1);
    });

    test('renameFolderWithPrompt renames only when the prompt returns a name',
        () async {
      // given
      final work = _folder('f2', 'Work', 1);
      when(() => facade.renameFolder(any(), any()))
          .thenAnswer((_) async => work);
      final notifications = locator<AppBoxKitNotificationService>()
          as FakeAppBoxKitNotificationService;
      final vm = ShowcaseNotesViewModel();
      addTearDown(vm.dispose);

      // when — the user cancels the prompt
      await vm.renameFolderWithPrompt(work);

      // then
      verifyNever(() => facade.renameFolder(any(), any()));

      // when — the user enters a new name
      notifications.promptResult = 'Jobs';
      await vm.renameFolderWithPrompt(work);

      // then
      verify(() => facade.renameFolder(work, 'Jobs')).called(1);
    });

    test('confirmDeleteFolder deletes only when the user confirms', () async {
      // given
      final work = _folder('f2', 'Work', 1);
      when(() => facade.deleteFolder(any())).thenAnswer((_) async {});
      final notifications = locator<AppBoxKitNotificationService>()
          as FakeAppBoxKitNotificationService;
      final vm = ShowcaseNotesViewModel();
      addTearDown(vm.dispose);

      // when — the user cancels the confirmation (default confirmResult)
      await vm.confirmDeleteFolder(work);

      // then — the facade never hears about it
      verifyNever(() => facade.deleteFolder(any()));

      // when — the user confirms
      notifications.confirmResult = true;
      await vm.confirmDeleteFolder(work);

      // then
      verify(() => facade.deleteFolder(work)).called(1);
    });

    test('signOut delegates to the facade', () async {
      // given
      when(() => facade.signOut()).thenAnswer((_) async {});
      final vm = ShowcaseNotesViewModel();
      addTearDown(vm.dispose);

      // when
      await vm.signOut();

      // then
      verify(() => facade.signOut()).called(1);
    });
  });
}
