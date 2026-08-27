import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
import 'package:arxa_kit_cairn/arxa_kit_cairn_testing.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_ui_library/arxa_kit_testing.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:arxa_kit_showcase_app/app/app_data.dart';
import 'package:arxa_kit_showcase_app/data/models/showcase_notes_models/showcase_note_attachment_model.dart';
import 'package:arxa_kit_showcase_app/data/schemas/showcase_notes_schemas/showcase_note_folder_schema.dart';
import 'package:arxa_kit_showcase_app/enums/showcase_notes_enums/enums.dart';
import 'package:arxa_kit_showcase_app/services/showcase_notes_services/adapters/showcase_notes_media_adapter_service.dart';
import 'package:arxa_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';
import 'package:arxa_kit_showcase_app/services/showcase_notes_services/repositories/showcase_notes_repository_service.dart';

class _MockMediaAdapter extends Mock
    implements ShowcaseNotesMediaAdapterService {}

/// The Phase-5b showcase smoke: the REAL Notes facade/repo stack boots over
/// the cairn backend (localOnly, fake engine — no native library in tests) and
/// notes round-trip CRUD unchanged. Everything above the kit/data seam —
/// models, codecs, facade ops, watch streams — is the app's own, untouched.
///
/// Mirror of notes_facade_test.dart's boot, with ONLY the backend swapped at
/// AppData.initialize's config parameter. Fixtures are not seeded under the
/// plugin backend (kit/data loads them only for seed) — the suite creates the
/// rows it reads, and stays order-independent by only mutating its own.
void main() {
  late ShowcaseNotesFacadeService notes;

  /// folderId is a REFERENCE column — stored canonicalized (v5 uuid), like
  /// the app's real folder rows.
  String folderId(String key) => arxaKitLocator<ArxaKitIdService>()
      .canonicalId(kShowcaseNoteFoldersTable, key);

  setUpAll(() async {
    registerFallbackValue(_attachmentForSmoke());
    setupArxaKitUiServices();
    arxaKitLocator
      ..registerLazySingleton(() => ArxaKitErrorService())
      ..registerLazySingleton<ArxaKitNotificationService>(
          () => FakeArxaKitNotificationService())
      ..registerLazySingleton<ShowcaseNotesRepositoryService>(
          () => ShowcaseNotesRepositoryService())
      ..registerLazySingleton<ShowcaseNotesFacadeService>(
          () => ShowcaseNotesFacadeService());
    final media = _MockMediaAdapter();
    when(() => media.deleteFile(any())).thenAnswer((_) async {});
    arxaKitLocator
        .registerSingleton<ShowcaseNotesMediaAdapterService>(media);

    final engine = FakeCairnEngine();
    await AppData.initialize(
      config: ArxaKitDataConfig(
        backend: ArxaKitDataBackend.plugin,
        plugin: ArxaKitCairnBackend(
          config: const ArxaKitCairnConfig(), // localOnly — the D2 free tier
          openDatabase: cairnLocalOpenForTest(engine),
        ),
      ),
    );
    notes = arxaKitLocator<ShowcaseNotesFacadeService>();
  });

  tearDownAll(() async {
    ArxaKitData.resetForTesting();
    await arxaKitLocator.reset();
  });

  test(
      'notes.note-crud.create-a-note — create persists and the live stream serves it (cairn backend)',
      () async {
    // given a fresh note through the facade op
    final created = await notes.createNote('smoke-owner', 'smoke-folder');

    // then the one-shot read and the live stream agree on the stored row
    final live = await notes.notesIn$('smoke-owner').first;
    expect(live.map((n) => n.id), contains(created.id));
    final fetched = await notes.note$(created.id).first;
    expect(fetched!.folderId, folderId('smoke-folder'));
    expect(fetched.body, '');
  });

  test(
      'notes.note-crud.edit-a-note — saveBody patches the body and keeps the rest (cairn backend)',
      () async {
    // given a note
    final created = await notes.createNote('smoke-owner', 'smoke-folder');

    // when the body saves
    final saved = await notes.saveBody(created, 'hello from cairn');

    // then the patch landed (and the concurrent-safe diff left the rest)
    expect(saved.body, 'hello from cairn');
    expect(saved.folderId, folderId('smoke-folder'));
    final reread = await notes.note$(created.id).first;
    expect(reread!.body, 'hello from cairn');
  });

  test(
      'notes.pin-notes.pin-a-note-to-the-top-of-the-inbox — togglePin flips the boolean column (cairn backend)',
      () async {
    // Booleans cross the WS2 view encoding as 0/1 — this op is the pin on
    // the read-normalization path.
    final created = await notes.createNote('smoke-owner', 'smoke-folder');
    expect(created.pinned, isFalse);

    final pinnedNote = await notes.togglePin(created);
    expect(pinnedNote.pinned, isTrue);
    expect((await notes.note$(created.id).first)!.pinned, isTrue);
  });

  test(
      'notes.trash-and-restore.trash-a-note — trash hides from notesIn\$, restore brings it back (cairn backend)',
      () async {
    // given a live note
    final created = await notes.createNote('trash-owner', 'smoke-folder');

    // when it trashes (a timestamptz write + a pinned=false patch)
    final trashed = await notes.moveToTrash(created);

    // then it leaves the live listing and lands in trash$
    expect(trashed.isDeleted, isTrue);
    final live = await notes.notesIn$('trash-owner').first;
    expect(live.map((n) => n.id), isNot(contains(created.id)));
    final trash = await notes.trash$('trash-owner').first;
    expect(trash.map((n) => n.id), contains(created.id));

    // and restore reverses it
    final restored = await notes.restore(trashed);
    expect(restored.isDeleted, isFalse);
    final relisted = await notes.notesIn$('trash-owner').first;
    expect(relisted.map((n) => n.id), contains(created.id));
  });

  test(
      'notes.note-crud.delete-a-note-forever — deletePermanently removes the row (cairn backend)',
      () async {
    // given a note with no attachments
    final created = await notes.createNote('purge-owner', 'smoke-folder');

    // when it is purged
    await notes.deletePermanently(created);

    // then every read surface agrees it is gone
    expect(await notes.note$(created.id).first, isNull);
    final live = await notes.notesIn$('purge-owner').first;
    expect(live.map((n) => n.id), isNot(contains(created.id)));
  });
}

ShowcaseNoteAttachmentModel _attachmentForSmoke() => ShowcaseNoteAttachmentModel(
      id: 'smoke-attachment',
      kind: ShowcaseNoteAttachmentKind.photo,
      fileName: 'smoke.jpg',
      createdAt: DateTime.utc(2026, 1, 1),
    );
