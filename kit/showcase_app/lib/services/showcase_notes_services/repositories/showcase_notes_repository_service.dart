/// The notes repository — the app-level persistence seam over the kit's
/// generic `ArxaKitRepository<T>`. It owns query construction
/// (ArxaKitQuery — filters, ordering, direction) and id minting, and
/// exposes raw single-table writes. It never aggregates or derives: counts,
/// sectioning, and cross-table composition are facade work. Watch streams
/// pass through from the kit; the facade wraps every call.
///
/// This is the store for the notes product. It saves notes and folders to the
/// database, reads them back with the right filters and sort order, and hands
/// out fresh ids when something new is created.
///
/// Requirements:
/// 1. [Read notes and folders] — notes.folders.browse-the-notes-in-a-folder
/// The owner's notes and folders are read back from the database.
/// 2. [Create a note] — notes.note-crud.create-a-note
/// A new note is constructed with a fresh id and written to storage.
/// 3. [Delete a note] — notes.note-crud.delete-a-note-forever
/// A note is removed from storage by id.
/// 4. [Create a folder] — notes.folders.create-a-folder
/// A new folder is constructed with a fresh id and written to storage.
/// 5. [Move a note into a folder] — notes.folders.move-a-note-into-a-folder
/// A note's folder assignment is changed through a narrow patch write.
/// 6. [Query construction]
/// Filters, ordering, and direction are assembled into ArxaKitQuery objects.
/// 7. [Id minting]
/// New notes and folders get a UUID v4 id before they reach the kit.
/// 8. [Patch writes]
/// Only the columns that differ between original and patched hit storage.
///
/// Relationships:
///
///         ┌──────────────┐
///         │ notes facade │
///         └──────────────┘
///         ACT ▼    ▲ STRM
///         [1-10]   [1-5]
///      ┌────────────────────┐
///      │  notes repository  │
///      └────────────────────┘
///      ACT ▼          ▲ STRM
///      [1-6]          [1-2]
///    ┌────────────────────────┐
///    │ ArxaKitRepository<T> │
///    └────────────────────────┘
///    ════════ abxAction ════════
///
///  streams (STRM)            actions (ACT)
///    1. foldersOf              1. watchAll
///    2. allNotesOf             2. watchById
///    3. allFolders             3. getAll
///    4. allNotes               4. upsert
///    5. watchNote              5. delete
///                              6. patch
///
/// History: git log --follow -- kit/showcase_app/lib/services/showcase_notes_services/repositories/showcase_notes_repository_service.dart
library;

import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show arxaKitLocator;
import 'package:uuid/uuid.dart';

import 'package:arxa_kit_showcase_app/data/models/showcase_notes_models/showcase_note_model.dart';
import 'package:arxa_kit_showcase_app/data/models/showcase_notes_models/showcase_note_folder_model.dart';

class ShowcaseNotesRepositoryService {
  // ── Setup ──────────────────────────────────────────────────────────────────

  static const _uuid = Uuid();

  ArxaKitRepository<ShowcaseNoteModel> get _notes =>
      arxaKitLocator<ArxaKitRepository<ShowcaseNoteModel>>();
  ArxaKitRepository<ShowcaseNoteFolderModel> get _folders =>
      arxaKitLocator<ArxaKitRepository<ShowcaseNoteFolderModel>>();

  // ── Reads ──────────────────────────────────────────────────────────────────

  /// [1. Read notes and folders] The owner's folders, in display order.
  Stream<List<ShowcaseNoteFolderModel>> foldersOf(String owner) =>
      _folders.watchAll(ArxaKitQuery(
        filters: [ArxaKitFilter.eq('owner', owner)],
        orderBy: 'sort_order',
      ));

  /// [1. Read notes and folders] Every note the owner has, live and deleted,
  /// newest-edited first — the single upstream the facade's derived streams map
  /// over.
  Stream<List<ShowcaseNoteModel>> allNotesOf(String owner) =>
      _notes.watchAll(ArxaKitQuery(
        filters: [ArxaKitFilter.eq('owner', owner)],
        orderBy: 'updated_at',
        descending: true,
      ));

  /// [1. Read notes and folders] Every owner's folders (admin visibility — deliberately unfiltered).
  Stream<List<ShowcaseNoteFolderModel>> allFolders() =>
      _folders.watchAll(const ArxaKitQuery(orderBy: 'created_at'));

  /// [1. Read notes and folders] Every owner's notes (admin visibility — deliberately unfiltered).
  Stream<List<ShowcaseNoteModel>> allNotes() =>
      _notes.watchAll(const ArxaKitQuery());

  /// [1. Read notes and folders] Live watch on a single note by id.
  Stream<ShowcaseNoteModel?> watchNote(String id) => _notes.watchById(id);

  /// [1. Read notes and folders] One-shot fetch of the owner's notes (for multi-step mutations).
  Future<List<ShowcaseNoteModel>> notesOf(String owner) => _notes
      .getAll(ArxaKitQuery(filters: [ArxaKitFilter.eq('owner', owner)]));

  /// [1. Read notes and folders] One-shot fetch of a folder's notes (for cascade delete).
  Future<List<ShowcaseNoteModel>> notesInFolder(String folderId) =>
      _notes.getAll(
          ArxaKitQuery(filters: [ArxaKitFilter.eq('folder_id', folderId)]));

  // ── Writes ─────────────────────────────────────────────────────────────────

  /// [2. Create a note][7. Id minting] Mints a fresh id and constructs the note row.
  ShowcaseNoteModel newNote(String owner, String folderId) {
    final now = DateTime.now().toUtc();
    return ShowcaseNoteModel(
      id: _uuid.v4(),
      folderId: folderId,
      owner: owner,
      body: '',
      createdAt: now,
      updatedAt: now,
    );
  }

  /// [4. Create a folder][7. Id minting] Mints a fresh id and constructs the folder row.
  ShowcaseNoteFolderModel newFolder(String owner, String name,
          {required int sortOrder}) =>
      ShowcaseNoteFolderModel(
        id: _uuid.v4(),
        name: name,
        sortOrder: sortOrder,
        owner: owner,
        createdAt: DateTime.now().toUtc(),
      );

  /// [2. Create a note] Writes the note (create or replace).
  Future<ShowcaseNoteModel> upsertNote(ShowcaseNoteModel note) =>
      _notes.upsert(note);

  /// [3. Delete a note] Removes the note by id.
  Future<void> deleteNote(String id) => _notes.delete(id);

  /// [4. Create a folder] Writes the folder (create or replace).
  Future<ShowcaseNoteFolderModel> upsertFolder(
          ShowcaseNoteFolderModel folder) =>
      _folders.upsert(folder);

  /// Removes the folder by id (cascade is facade work).
  Future<void> deleteFolder(String id) => _folders.delete(id);

  /// [5. Move a note into a folder][8. Patch writes] Writes only the columns
  /// that changed, so concurrent edits to other columns survive.
  Future<ShowcaseNoteModel> patchNote(
          ShowcaseNoteModel original, ShowcaseNoteModel patched) =>
      _notes.patch(original, patched);

  /// [8. Patch writes] Narrow column update for an existing folder.
  Future<ShowcaseNoteFolderModel> patchFolder(
          ShowcaseNoteFolderModel original, ShowcaseNoteFolderModel patched) =>
      _folders.patch(original, patched);
}
