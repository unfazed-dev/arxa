import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart' show appBoxKitLocator;
import 'package:uuid/uuid.dart';

import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_model.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_folder_model.dart';

/// Notes-domain gateway over the kit's `AppBoxKitRepository<ShowcaseNoteModel>` / `<ShowcaseNoteFolderModel>`
/// (registered by `AppBoxKitData.initialize`). This is the app-level repository seam:
/// it owns query construction and id minting, and exposes raw single-table
/// writes. It never aggregates or derives — counts, sectioning and cross-table
/// composition are facade work (swap rule 2). See ADR / DESIGN-ARCHITECTURE:
/// query work lives in the repository, aggregation in the facade.
class ShowcaseNotesRepositoryService {
  static const _uuid = Uuid();

  AppBoxKitRepository<ShowcaseNoteModel> get _notes => appBoxKitLocator<AppBoxKitRepository<ShowcaseNoteModel>>();
  AppBoxKitRepository<ShowcaseNoteFolderModel> get _folders => appBoxKitLocator<AppBoxKitRepository<ShowcaseNoteFolderModel>>();

  // -- Reads (own the AppBoxKitQuery) ----------------------------------------------

  /// The owner's folders, in display order.
  Stream<List<ShowcaseNoteFolderModel>> foldersOf(String owner) => _folders.watchAll(AppBoxKitQuery(
        filters: [AppBoxKitFilter.eq('owner', owner)],
        orderBy: 'sort_order',
      ));

  /// Every note the owner has, live and deleted, newest-edited first — the
  /// single upstream the facade's derived streams map over.
  Stream<List<ShowcaseNoteModel>> allNotesOf(String owner) => _notes.watchAll(AppBoxKitQuery(
        filters: [AppBoxKitFilter.eq('owner', owner)],
        orderBy: 'updated_at',
        descending: true,
      ));

  /// Every owner's folders (admin visibility — deliberately unfiltered).
  Stream<List<ShowcaseNoteFolderModel>> allFolders() =>
      _folders.watchAll(const AppBoxKitQuery(orderBy: 'created_at'));

  /// Every owner's notes (admin visibility — deliberately unfiltered).
  Stream<List<ShowcaseNoteModel>> allNotes() => _notes.watchAll(const AppBoxKitQuery());

  Stream<ShowcaseNoteModel?> watchNote(String id) => _notes.watchById(id);

  /// One-shot fetch of the owner's notes (for multi-step mutations).
  Future<List<ShowcaseNoteModel>> notesOf(String owner) =>
      _notes.getAll(AppBoxKitQuery(filters: [AppBoxKitFilter.eq('owner', owner)]));

  /// One-shot fetch of a folder's notes (for cascade delete).
  Future<List<ShowcaseNoteModel>> notesInFolder(String folderId) =>
      _notes.getAll(AppBoxKitQuery(filters: [AppBoxKitFilter.eq('folder_id', folderId)]));

  // -- Id minting ------------------------------------------------------------

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

  ShowcaseNoteFolderModel newFolder(String owner, String name, {required int sortOrder}) =>
      ShowcaseNoteFolderModel(
        id: _uuid.v4(),
        name: name,
        sortOrder: sortOrder,
        owner: owner,
        createdAt: DateTime.now().toUtc(),
      );

  // -- Writes (raw single-table ops; the facade wraps these in `mutate`) -----

  Future<ShowcaseNoteModel> upsertNote(ShowcaseNoteModel note) => _notes.upsert(note);
  Future<void> deleteNote(String id) => _notes.delete(id);
  Future<ShowcaseNoteFolderModel> upsertFolder(ShowcaseNoteFolderModel folder) => _folders.upsert(folder);
  Future<void> deleteFolder(String id) => _folders.delete(id);

  /// Narrow writes for existing rows: only the columns that differ between
  /// [original] and [patched] hit storage, so concurrent edits to other
  /// columns (another surface, another device) survive. Default for every
  /// mutation of an existing row; `upsert` is for creates.
  Future<ShowcaseNoteModel> patchNote(ShowcaseNoteModel original, ShowcaseNoteModel patched) =>
      _notes.patch(original, patched);
  Future<ShowcaseNoteFolderModel> patchFolder(ShowcaseNoteFolderModel original, ShowcaseNoteFolderModel patched) =>
      _folders.patch(original, patched);
}
