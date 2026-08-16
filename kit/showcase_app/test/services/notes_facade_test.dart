import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_ui_library/appbox_kit_testing.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_model.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_attachment_model.dart';
import 'package:appbox_kit_showcase_app/data/schemas/showcase_notes_schemas/showcase_note_folder_schema.dart';
import 'package:appbox_kit_showcase_app/enums/showcase_notes_enums/enums.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/adapters/showcase_notes_media_adapter_service.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/repositories/showcase_notes_repository_service.dart';
import 'package:appbox_kit_showcase_app/app/app_data.dart';

class _MockMediaAdapter extends Mock
    implements ShowcaseNotesMediaAdapterService {}

ShowcaseNoteAttachmentModel _attachment(String id) =>
    ShowcaseNoteAttachmentModel(
      id: id,
      kind: ShowcaseNoteAttachmentKind.photo,
      fileName: '$id.jpg',
      createdAt: DateTime.utc(2026, 1, 1),
    );

/// Registers a fresh recording mock of the media adapter for one test (the
/// suite otherwise never resolves it — only attachment/purge paths do).
_MockMediaAdapter _registerMediaMock() {
  final media = _MockMediaAdapter();
  when(() => media.deleteFile(any())).thenAnswer((_) async {});
  appBoxKitLocator.registerSingleton<ShowcaseNotesMediaAdapterService>(media);
  addTearDown(
      () => appBoxKitLocator.unregister<ShowcaseNotesMediaAdapterService>());
  return media;
}

/// Smoke tests for the Notes data slice over the REAL shipped fixtures —
/// the same JSON the app seeds from, loaded off disk. One initialize for the
/// whole file (AppBoxKitData is static state; see kit_data_initialize_test.dart in
/// appbox_kit_data for the reasoning) — tests share the store and stay
/// order-independent by only mutating rows they create.
class _DiskAssetReader implements AppBoxKitAssetReader {
  static const _prefix = 'packages/appbox_kit_showcase_app/';

  @override
  Future<String> readString(String path) async {
    // Package-asset keys map straight onto this package's source tree.
    final stripped =
        path.startsWith(_prefix) ? path.substring(_prefix.length) : path;
    return File(stripped).readAsString();
  }
}

void main() {
  late ShowcaseNotesFacadeService notes;
  late String evanId;

  setUpAll(() async {
    registerFallbackValue(_attachment('fallback'));
    // AppBoxKitAction managers resolve these lazily on first execute() — the
    // kit's own setup registers Talker + the stacked UI service bases.
    setupAppBoxKitUiServices();
    appBoxKitLocator
      ..registerLazySingleton(() => AppBoxKitErrorService())
      // Fake: the real service's CNToast path needs a mounted navigator
      // context, which a data-layer suite doesn't have. Recording double from
      // package:appbox_kit_ui_library/appbox_kit_testing.dart.
      ..registerLazySingleton<AppBoxKitNotificationService>(
          () => FakeAppBoxKitNotificationService())

      // Registered by the @StackedApp appBoxKitLocator in the app; this suite stays
      // self-contained (data layer only), so it registers them itself.
      ..registerLazySingleton<ShowcaseNotesRepositoryService>(
          () => ShowcaseNotesRepositoryService())
      ..registerLazySingleton<ShowcaseNotesFacadeService>(
          () => ShowcaseNotesFacadeService());

    await AppData.initialize(
      // Snapshot persistence needs a platform channel; tests run in-memory.
      config: const AppBoxKitDataConfig(
        backend: AppBoxKitDataBackend.seed,
        auth: AppBoxKitAuthConfig(fakeUsersAsset: AppData.fakeUsersAsset),
      ),
      assetReader: _DiskAssetReader(),
    );

    notes = appBoxKitLocator<ShowcaseNotesFacadeService>();
    final session = await notes.auth
        .signInWithEmailPassword(email: 'evan@seed.local', password: 'x');
    evanId = session.user.id;
  });

  tearDownAll(() async {
    AppBoxKitData.resetForTesting();
    await appBoxKitLocator.reset();
  });

  test(
      'auth-and-accounts.sign-in.sign-in-with-email-and-otp — fake sign-in resolves the fixture user and its canonical id',
      () {
    final idService = appBoxKitLocator<AppBoxKitIdService>();
    expect(evanId, idService.canonicalId(kAppBoxKitAuthUsersTable, 'user-1'));
  });

  test(
      'notes.folders.browse-the-notes-in-a-folder — notesIn\$ emits only the owner\'s live notes',
      () async {
    final live = await notes.notesIn$(evanId).first;
    expect(live, hasLength(7)); // 8 evan fixtures minus the deleted draft
    expect(live.any((n) => n.title == 'Old draft'), isFalse);
    expect(live.any((n) => n.title == 'Guest note'), isFalse);
  });

  test(
      'notes.folders.browse-the-notes-in-a-folder — overview\$ derives folder counts, all count, and trash count',
      () async {
    final overview = await notes.overview$(evanId).first;
    expect(overview.folders.map((f) => f.name), ['Notes', 'Work', 'Personal']);
    expect(overview.allCount, 7);
    expect(overview.trashCount, 1);

    final idService = appBoxKitLocator<AppBoxKitIdService>();
    String fid(String key) =>
        idService.canonicalId(kShowcaseNoteFoldersTable, key);
    expect(overview.liveCountByFolder[fid('folder-work')], 3);
    expect(overview.liveCountByFolder[fid('folder-personal')], 3);
    expect(overview.liveCountByFolder[fid('folder-notes')], 1);
  });

  test(
      'notes.trash-and-restore.trash-a-note — trash\$ holds the seeded deleted draft',
      () async {
    final trash = await notes.trash$(evanId).first;
    expect(trash.map((n) => n.title), ['Old draft']);
  });

  test(
      'search-and-attachments.search.search-notes-by-text — search\$ filters bodies case-insensitively',
      () async {
    final hits = await notes.search$(evanId, 'ESPRESSO').first;
    expect(hits.map((n) => n.title), ['Groceries']);
  });

  test(
      'notes.pin-notes.pin-a-note-to-the-top-of-the-inbox — groupNotes buckets by iOS Notes sections, pinned first',
      () {
    final now = DateTime(2026, 7, 12, 12);
    ShowcaseNoteModel note(String id, DateTime updatedAt,
            {bool pinned = false}) =>
        ShowcaseNoteModel(
          id: id,
          folderId: 'f',
          owner: 'o',
          body: id,
          pinned: pinned,
          createdAt: updatedAt,
          updatedAt: updatedAt,
        );

    final groups = ShowcaseNotesFacadeService.groupNotes([
      note('pinned-old', DateTime(2024, 1, 1), pinned: true),
      note('today', DateTime(2026, 7, 12, 8)),
      note('yesterday', DateTime(2026, 7, 11, 23)),
      note('last-week', DateTime(2026, 7, 6)),
      note('last-month', DateTime(2026, 6, 20)),
      note('march', DateTime(2026, 3, 2)),
      note('old-year', DateTime(2025, 12, 30)),
    ], now);

    expect(groups.map((g) => g.label), [
      'Pinned',
      'Today',
      'Yesterday',
      'Previous 7 Days',
      'Previous 30 Days',
      'March',
      '2025',
    ]);
    expect(groups.first.notes.single.id, 'pinned-old');
  });

  test(
      'notes.note-crud.create-a-note — mutation round-trip: create → save (notes.note-crud.edit-a-note) → pin (notes.pin-notes.pin-a-note-to-the-top-of-the-inbox) → trash (notes.trash-and-restore.trash-a-note) → restore (notes.trash-and-restore.restore-a-trashed-note) → purge (notes.note-crud.delete-a-note-forever)',
      () async {
    final idService = appBoxKitLocator<AppBoxKitIdService>();
    final folderId =
        idService.canonicalId(kShowcaseNoteFoldersTable, 'folder-notes');

    final created = await notes.createNote(evanId, folderId);
    expect(created.body, isEmpty);
    expect(created.title, 'New Note');

    final saved = await notes.saveBody(created, 'Round trip\nsecond line');
    expect(saved.title, 'Round trip');
    expect(saved.snippet, 'second line');

    final pinned = await notes.togglePin(saved);
    expect(pinned.pinned, isTrue);

    final trashed = await notes.moveToTrash(pinned);
    expect(trashed.isDeleted, isTrue);
    expect(trashed.pinned, isFalse, reason: 'trashing unpins, like iOS');
    final trash = await notes.trash$(evanId).first;
    expect(trash.map((n) => n.id), contains(created.id));

    final restored = await notes.restore(trashed);
    expect(restored.isDeleted, isFalse);

    await notes.deletePermanently(restored);
    final live = await notes.notesIn$(evanId).first;
    expect(live.map((n) => n.id), isNot(contains(created.id)));
  });

  test(
      'notes.trash-and-restore.trash-a-note — deleteFolder sends its live notes to Recently Deleted',
      () async {
    final folder = await notes.createFolder(evanId, 'Doomed', sortOrder: 99);
    final doomed = await notes.createNote(evanId, folder.id);

    await notes.deleteFolder(folder);

    final overview = await notes.overview$(evanId).first;
    expect(overview.folders.map((f) => f.name), isNot(contains('Doomed')));
    final trash = await notes.trash$(evanId).first;
    expect(trash.map((n) => n.id), contains(doomed.id));

    // Leave the store as found for order-independence.
    final row = trash.firstWhere((n) => n.id == doomed.id);
    await notes.deletePermanently(row);
  });

  test(
      'notes.folders.move-a-note-into-a-folder — moving a note changes which folder stream it appears in',
      () async {
    final source =
        await notes.createFolder(evanId, 'Move source', sortOrder: 100);
    final target =
        await notes.createFolder(evanId, 'Move target', sortOrder: 101);
    final note = await notes.createNote(evanId, source.id);

    Future<List<String>> idsIn(String folderId) async =>
        (await notes.notesIn$(evanId, folderId: folderId).first)
            .map((n) => n.id)
            .toList();

    expect(await idsIn(source.id), contains(note.id));
    expect(await idsIn(target.id), isNot(contains(note.id)));

    final moved = await notes.moveNoteToFolder(note, target.id);
    expect(moved.folderId, target.id);
    expect(await idsIn(source.id), isNot(contains(note.id)));
    expect(await idsIn(target.id), contains(note.id));

    // Guards — identical() proves the no-op returned the input without a
    // repository write.
    expect(identical(await notes.moveNoteToFolder(moved, target.id), moved),
        isTrue,
        reason: 'same-folder move is a no-op');

    await notes.auth.signOut();
    addTearDown(() => notes.auth
        .signInWithEmailPassword(email: 'evan@seed.local', password: 'x'));
    expect(identical(await notes.moveNoteToFolder(moved, source.id), moved),
        isTrue,
        reason: 'signed-out move is a no-op');
    await notes.auth
        .signInWithEmailPassword(email: 'evan@seed.local', password: 'x');

    final trashed = await notes.moveToTrash(moved);
    expect(
        (await notes.moveNoteToFolder(trashed, source.id)).folderId, target.id,
        reason: 'trashed notes stay put — restore returns to the folder');

    // Leave the store as found for order-independence.
    await notes.deletePermanently(trashed);
    await notes.deleteFolder(source);
    await notes.deleteFolder(target);
  });

  test(
      'auth-and-accounts.sign-in.sign-in-with-email-and-otp — per-owner isolation: the guest sees only guest notes',
      () async {
    final guest = await notes.auth
        .signInWithEmailPassword(email: 'guest@seed.local', password: 'x');
    addTearDown(() => notes.auth
        .signInWithEmailPassword(email: 'evan@seed.local', password: 'x'));

    final live = await notes.notesIn$(guest.user.id).first;
    expect(live.map((n) => n.title), ['Guest note']);

    final overview = await notes.overview$(guest.user.id).first;
    expect(overview.folders.map((f) => f.name), ['Notes']);
    expect(overview.trashCount, 0);
  });

  test(
      'notes.trash-and-restore.trash-a-note — a trash write preserves a concurrent body edit on the same note',
      () async {
    final idService = appBoxKitLocator<AppBoxKitIdService>();
    final kitRepo = appBoxKitLocator<AppBoxKitRepository<ShowcaseNoteModel>>();
    final folderId =
        idService.canonicalId(kShowcaseNoteFoldersTable, 'folder-notes');
    final note = await notes.createNote(evanId, folderId);

    // A second surface edits the body after the editor read `note`.
    await kitRepo.upsert(note.copyWith(
        body: 'concurrent edit', updatedAt: DateTime.now().toUtc()));

    final trashed = await notes.moveToTrash(note);

    expect(trashed.isDeleted, isTrue);
    expect(trashed.body, 'concurrent edit',
        reason:
            'trash writes only deleted_at/pinned — never clobbers another edit');

    // Leave the store as found for order-independence.
    await notes.deletePermanently(trashed);
  });

  test(
      'notes.pin-notes.pin-a-note-to-the-top-of-the-inbox — a pin write preserves a concurrent body edit on the same note',
      () async {
    final idService = appBoxKitLocator<AppBoxKitIdService>();
    final kitRepo = appBoxKitLocator<AppBoxKitRepository<ShowcaseNoteModel>>();
    final folderId =
        idService.canonicalId(kShowcaseNoteFoldersTable, 'folder-notes');
    final note = await notes.createNote(evanId, folderId);

    await kitRepo.upsert(note.copyWith(
        body: 'concurrent edit', updatedAt: DateTime.now().toUtc()));

    final pinned = await notes.togglePin(note);

    expect(pinned.pinned, isTrue);
    expect(pinned.body, 'concurrent edit');

    // Leave the store as found for order-independence.
    await notes.deletePermanently(pinned);
  });

  test(
      'search-and-attachments.media-attachments.attach-a-photo-to-a-note — removeAttachment unlinks the row first, then deletes the file',
      () async {
    // given — a note carrying one photo, and a media mock that inspects the
    // store at the moment its delete runs
    final media = _registerMediaMock();
    final idService = appBoxKitLocator<AppBoxKitIdService>();
    final folderId =
        idService.canonicalId(kShowcaseNoteFoldersTable, 'folder-notes');
    final created = await notes.createNote(evanId, folderId);
    final withPhoto = await notes.addAttachment(created, _attachment('p1'));
    when(() => media.deleteFile(any())).thenAnswer((_) async {
      final current = await notes.note$(withPhoto.id).first;
      expect(current!.attachments, isEmpty,
          reason: 'the reference is gone before the file delete runs');
    });

    // when
    final updated =
        await notes.removeAttachment(withPhoto, withPhoto.attachments.single);

    // then
    expect(updated.attachments, isEmpty);
    verify(() => media.deleteFile(any())).called(1);

    // Leave the store as found.
    await notes.deletePermanently(updated);
  });

  test(
      'notes.note-crud.delete-a-note-forever — purging a note deletes its attachment files',
      () async {
    // given
    final media = _registerMediaMock();
    final idService = appBoxKitLocator<AppBoxKitIdService>();
    final folderId =
        idService.canonicalId(kShowcaseNoteFoldersTable, 'folder-notes');
    final created = await notes.createNote(evanId, folderId);
    final withMedia = await notes.addAttachment(created, _attachment('p1'));

    // when
    await notes.deletePermanently(withMedia);

    // then — the row is gone AND its binary cleanup ran (no orphans)
    final live = await notes.notesIn$(evanId).first;
    expect(live.map((n) => n.id), isNot(contains(created.id)));
    verify(() => media.deleteFile(any())).called(1);
  });

  test(
      'notes.trash-and-restore.trash-a-note — emptying the trash deletes every trashed note\'s files',
      () async {
    // given — a trashed note carrying a photo
    final media = _registerMediaMock();
    final idService = appBoxKitLocator<AppBoxKitIdService>();
    final folderId =
        idService.canonicalId(kShowcaseNoteFoldersTable, 'folder-notes');
    final created = await notes.createNote(evanId, folderId);
    final withPhoto = await notes.addAttachment(created, _attachment('p1'));
    await notes.moveToTrash(withPhoto);

    // when
    await notes.emptyTrash(evanId);

    // then
    expect(await notes.trash$(evanId).first, isEmpty);
    verify(() => media.deleteFile(any())).called(1);
    // NB: this empties the seeded 'Old draft' too — it relies on declaration
    // order (the trash$ seed test runs earlier in this file).
  });

  test(
      'search-and-attachments.media-attachments.attach-a-photo-to-a-note — a cancelled picker leaves the note untouched (no write, no attach)',
      () async {
    // given — the user backs out of the picker
    final media = _registerMediaMock();
    when(() => media.pickPhoto(fromCamera: any(named: 'fromCamera')))
        .thenAnswer((_) async => null);
    final idService = appBoxKitLocator<AppBoxKitIdService>();
    final folderId =
        idService.canonicalId(kShowcaseNoteFoldersTable, 'folder-notes');
    final created = await notes.createNote(evanId, folderId);

    // when
    final result = await notes.addPhoto(created, fromCamera: false);

    // then — identical() proves no repository write happened
    expect(identical(result, created), isTrue);

    await notes.deletePermanently(created);
  });

  test(
      'search-and-attachments.media-attachments.attach-an-audio-recording-to-a-note — a stopped recording lands on the note through the facade',
      () async {
    // given
    final media = _registerMediaMock();
    final memo = ShowcaseNoteAttachmentModel(
      id: 'v1',
      kind: ShowcaseNoteAttachmentKind.audio,
      fileName: 'v1.m4a',
      durationMs: 7000,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    when(() => media.stopRecording()).thenAnswer((_) async => memo);
    final idService = appBoxKitLocator<AppBoxKitIdService>();
    final folderId =
        idService.canonicalId(kShowcaseNoteFoldersTable, 'folder-notes');
    final created = await notes.createNote(evanId, folderId);

    // when
    final updated = await notes.addVoiceNote(created);

    // then
    expect(updated.attachments.single.id, 'v1');
    expect(updated.attachments.single.kind, ShowcaseNoteAttachmentKind.audio);
    expect(updated.attachments.single.durationMs, 7000);

    await notes.deletePermanently(updated);
  });
}
