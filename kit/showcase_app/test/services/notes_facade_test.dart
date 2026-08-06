import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_ui_library/appbox_kit_testing.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_model.dart';
import 'package:appbox_kit_showcase_app/data/schemas/showcase_notes_schemas/showcase_note_folder_schema.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/repositories/showcase_notes_repository_service.dart';
import 'package:appbox_kit_showcase_app/app/app_data.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';

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
    // AppBoxKitAction managers resolve these lazily on first execute().
    appBoxKitLocator
      ..registerLazySingleton(() => Talker())
      ..registerLazySingleton(() => AppBoxKitErrorService())
      ..registerLazySingleton(() => DialogService())
      ..registerLazySingleton(() => BottomSheetService())
      ..registerLazySingleton(() => SnackbarService())
      // Fake: the real service's CNToast path needs a mounted navigator
      // context, which a data-layer suite doesn't have. Recording double from
      // package:appbox_kit_ui_library/appbox_kit_testing.dart.
      ..registerLazySingleton<AppBoxKitNotificationService>(() => FakeAppBoxKitNotificationService())

      // Registered by the @StackedApp appBoxKitLocator in the app; this suite stays
      // self-contained (data layer only), so it registers them itself.
      ..registerLazySingleton<ShowcaseNotesRepositoryService>(() => ShowcaseNotesRepositoryService())
      ..registerLazySingleton<ShowcaseNotesFacadeService>(() => ShowcaseNotesFacadeService());

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

  test('fake sign-in resolves the fixture user and its canonical id', () {
    final idService = appBoxKitLocator<AppBoxKitIdService>();
    expect(evanId, idService.canonicalId(kAppBoxKitAuthUsersTable, 'user-1'));
  });

  test('notesIn\$ emits only the owner\'s live notes', () async {
    final live = await notes.notesIn$(evanId).first;
    expect(live, hasLength(7)); // 8 evan fixtures minus the deleted draft
    expect(live.any((n) => n.title == 'Old draft'), isFalse);
    expect(live.any((n) => n.title == 'Guest note'), isFalse);
  });

  test('overview\$ derives folder counts, all count, and trash count',
      () async {
    final overview = await notes.overview$(evanId).first;
    expect(overview.folders.map((f) => f.name), ['Notes', 'Work', 'Personal']);
    expect(overview.allCount, 7);
    expect(overview.trashCount, 1);

    final idService = appBoxKitLocator<AppBoxKitIdService>();
    String fid(String key) => idService.canonicalId(kShowcaseNoteFoldersTable, key);
    expect(overview.liveCountByFolder[fid('folder-work')], 3);
    expect(overview.liveCountByFolder[fid('folder-personal')], 3);
    expect(overview.liveCountByFolder[fid('folder-notes')], 1);
  });

  test('trash\$ holds the seeded deleted draft', () async {
    final trash = await notes.trash$(evanId).first;
    expect(trash.map((n) => n.title), ['Old draft']);
  });

  test('search\$ filters bodies case-insensitively', () async {
    final hits = await notes.search$(evanId, 'ESPRESSO').first;
    expect(hits.map((n) => n.title), ['Groceries']);
  });

  test('groupNotes buckets by iOS Notes sections, pinned first', () {
    final now = DateTime(2026, 7, 12, 12);
    ShowcaseNoteModel note(String id, DateTime updatedAt, {bool pinned = false}) => ShowcaseNoteModel(
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

  test('mutation round-trip: create → save → pin → trash → restore → purge',
      () async {
    final idService = appBoxKitLocator<AppBoxKitIdService>();
    final folderId = idService.canonicalId(kShowcaseNoteFoldersTable, 'folder-notes');

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

  test('deleteFolder sends its live notes to Recently Deleted', () async {
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

  test('per-owner isolation: the guest sees only guest notes', () async {
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
}
