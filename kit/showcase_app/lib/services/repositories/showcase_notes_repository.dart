import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:ui_library/ui_library.dart' show locator;
import 'package:uuid/uuid.dart';

import 'package:appbox_kit_showcase_app/models/showcase_note.dart';
import 'package:appbox_kit_showcase_app/models/showcase_note_folder.dart';

/// Notes-domain gateway over the kit's `KitRepository<ShowcaseNote>` / `<ShowcaseNoteFolder>`
/// (registered by `KitData.initialize`). This is the app-level repository seam:
/// it owns query construction and id minting, and exposes raw single-table
/// writes. It never aggregates or derives — counts, sectioning and cross-table
/// composition are facade work (swap rule 2). See ADR / DESIGN-ARCHITECTURE:
/// query work lives in the repository, aggregation in the facade.
class ShowcaseNotesRepository {
  static const _uuid = Uuid();

  KitRepository<ShowcaseNote> get _notes => locator<KitRepository<ShowcaseNote>>();
  KitRepository<ShowcaseNoteFolder> get _folders => locator<KitRepository<ShowcaseNoteFolder>>();

  // -- Reads (own the KitQuery) ----------------------------------------------

  /// The owner's folders, in display order.
  Stream<List<ShowcaseNoteFolder>> foldersOf(String owner) => _folders.watchAll(KitQuery(
        filters: [KitFilter.eq('owner', owner)],
        orderBy: 'sort_order',
      ));

  /// Every note the owner has, live and deleted, newest-edited first — the
  /// single upstream the facade's derived streams map over.
  Stream<List<ShowcaseNote>> allNotesOf(String owner) => _notes.watchAll(KitQuery(
        filters: [KitFilter.eq('owner', owner)],
        orderBy: 'updated_at',
        descending: true,
      ));

  /// Every owner's folders (admin visibility — deliberately unfiltered).
  Stream<List<ShowcaseNoteFolder>> allFolders() =>
      _folders.watchAll(const KitQuery(orderBy: 'created_at'));

  /// Every owner's notes (admin visibility — deliberately unfiltered).
  Stream<List<ShowcaseNote>> allNotes() => _notes.watchAll(const KitQuery());

  Stream<ShowcaseNote?> watchNote(String id) => _notes.watchById(id);

  /// One-shot fetch of the owner's notes (for multi-step mutations).
  Future<List<ShowcaseNote>> notesOf(String owner) =>
      _notes.getAll(KitQuery(filters: [KitFilter.eq('owner', owner)]));

  /// One-shot fetch of a folder's notes (for cascade delete).
  Future<List<ShowcaseNote>> notesInFolder(String folderId) =>
      _notes.getAll(KitQuery(filters: [KitFilter.eq('folder_id', folderId)]));

  // -- Id minting ------------------------------------------------------------

  ShowcaseNote newNote(String owner, String folderId) {
    final now = DateTime.now().toUtc();
    return ShowcaseNote(
      id: _uuid.v4(),
      folderId: folderId,
      owner: owner,
      body: '',
      createdAt: now,
      updatedAt: now,
    );
  }

  ShowcaseNoteFolder newFolder(String owner, String name, {required int sortOrder}) =>
      ShowcaseNoteFolder(
        id: _uuid.v4(),
        name: name,
        sortOrder: sortOrder,
        owner: owner,
        createdAt: DateTime.now().toUtc(),
      );

  // -- Writes (raw single-table ops; the facade wraps these in `mutate`) -----

  Future<ShowcaseNote> upsertNote(ShowcaseNote note) => _notes.upsert(note);
  Future<void> deleteNote(String id) => _notes.delete(id);
  Future<ShowcaseNoteFolder> upsertFolder(ShowcaseNoteFolder folder) => _folders.upsert(folder);
  Future<void> deleteFolder(String id) => _folders.delete(id);
}
