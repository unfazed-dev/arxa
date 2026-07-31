import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:ui_library/ui_library.dart' show locator;
import 'package:uuid/uuid.dart';

import 'package:appbox_kit_showcase_app/notes/models/note.dart';
import 'package:appbox_kit_showcase_app/notes/models/note_folder.dart';

/// Notes-domain gateway over the kit's `KitRepository<Note>` / `<NoteFolder>`
/// (registered by `KitData.initialize`). This is the app-level repository seam:
/// it owns query construction and id minting, and exposes raw single-table
/// writes. It never aggregates or derives — counts, sectioning and cross-table
/// composition are facade work (swap rule 2). See ADR / DESIGN-ARCHITECTURE:
/// query work lives in the repository, aggregation in the facade.
class NotesRepository {
  static const _uuid = Uuid();

  KitRepository<Note> get _notes => locator<KitRepository<Note>>();
  KitRepository<NoteFolder> get _folders => locator<KitRepository<NoteFolder>>();

  // -- Reads (own the KitQuery) ----------------------------------------------

  /// The owner's folders, in display order.
  Stream<List<NoteFolder>> foldersOf(String owner) => _folders.watchAll(KitQuery(
        filters: [KitFilter.eq('owner', owner)],
        orderBy: 'sort_order',
      ));

  /// Every note the owner has, live and deleted, newest-edited first — the
  /// single upstream the facade's derived streams map over.
  Stream<List<Note>> allNotesOf(String owner) => _notes.watchAll(KitQuery(
        filters: [KitFilter.eq('owner', owner)],
        orderBy: 'updated_at',
        descending: true,
      ));

  /// Every owner's folders (admin visibility — deliberately unfiltered).
  Stream<List<NoteFolder>> allFolders() =>
      _folders.watchAll(const KitQuery(orderBy: 'created_at'));

  /// Every owner's notes (admin visibility — deliberately unfiltered).
  Stream<List<Note>> allNotes() => _notes.watchAll(const KitQuery());

  Stream<Note?> watchNote(String id) => _notes.watchById(id);

  /// One-shot fetch of the owner's notes (for multi-step mutations).
  Future<List<Note>> notesOf(String owner) =>
      _notes.getAll(KitQuery(filters: [KitFilter.eq('owner', owner)]));

  /// One-shot fetch of a folder's notes (for cascade delete).
  Future<List<Note>> notesInFolder(String folderId) =>
      _notes.getAll(KitQuery(filters: [KitFilter.eq('folder_id', folderId)]));

  // -- Id minting ------------------------------------------------------------

  Note newNote(String owner, String folderId) {
    final now = DateTime.now().toUtc();
    return Note(
      id: _uuid.v4(),
      folderId: folderId,
      owner: owner,
      body: '',
      createdAt: now,
      updatedAt: now,
    );
  }

  NoteFolder newFolder(String owner, String name, {required int sortOrder}) =>
      NoteFolder(
        id: _uuid.v4(),
        name: name,
        sortOrder: sortOrder,
        owner: owner,
        createdAt: DateTime.now().toUtc(),
      );

  // -- Writes (raw single-table ops; the facade wraps these in `mutate`) -----

  Future<Note> upsertNote(Note note) => _notes.upsert(note);
  Future<void> deleteNote(String id) => _notes.delete(id);
  Future<NoteFolder> upsertFolder(NoteFolder folder) => _folders.upsert(folder);
  Future<void> deleteFolder(String id) => _folders.delete(id);
}
