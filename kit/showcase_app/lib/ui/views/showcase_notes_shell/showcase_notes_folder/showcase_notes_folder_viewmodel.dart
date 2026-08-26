/// The notes-list screen's viewmodel. The view calls actions in and reads
/// streams out: when the user does something, the matching action does the
/// work; when something changes, the new value flows down the stream and the
/// view redraws just the part listening to it. The viewmodel never touches the
/// view — swap the UI for any other and this file stays unchanged.
///
/// This is the business logic for the screen that lists notes. Depending on the
/// scope it shows all notes, the notes in one folder, or the notes in Recently
/// Deleted. A note can be created, pinned or unpinned, trashed, restored, or
/// deleted forever; when viewing a folder a note can be moved into another
/// folder. The list can be searched, and Recently Deleted can be emptied in one
/// step.
///
/// Requirements:
/// 1. [Browse notes] — browse-the-notes-in-a-folder
/// The notes in the current scope stream as sectioned groups.
/// 2. [Create a note] — create-a-note
/// A new note is created in the current folder and its id returned for navigation.
/// 3. [Pinning] — pin-a-note-to-the-top-of-the-inbox / unpin-a-pinned-note
/// A note can be pinned or unpinned.
/// 4. [Trash a note] — trash-a-note
/// A note moves to Recently Deleted.
/// 5. [Restore a note] — restore-a-trashed-note
/// A trashed note moves back.
/// 6. [Delete permanently] — delete-a-note-forever
/// A note is deleted forever, one at a time or by emptying trash — both behind a confirm gate.
/// 7. [Move to folder] — move-a-note-into-a-folder
/// A note moves into a folder.
///
/// Relationships:
///
///      ┌─────────────────────────┐
///      │    notes folder view    │
///      └─────────────────────────┘
///      ACT ▼               ▲ STRM
///      [1-10]              [1-5]
///   ┌───────────────────────────────┐
///   │    notes folder viewmodel     │
///   └───────────────────────────────┘
///            ACT ▼    ▲ STRM
///            [1-7]    [1-3]
///            ┌──────────────┐
///            │ notes facade │
///            └──────────────┘
///      ════════ abxAction ════════
///
///  streams (STRM)          actions (ACT)            commands (CMD)
///    1. folders$            1. setQuery              1. _confirmEmptyTrash
///    2. notes$              2. togglePin             2. _confirmDeletePermanently
///    3. query$              3. moveToTrash
///    4. title$              4. moveNoteToFolder
///    5. groups$             5. restore
///                          6. deletePermanently
///                          7. emptyTrash
///                          8. confirmEmptyTrash
///                          9. confirmDeletePermanently
///                         10. compose
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_viewmodel.dart
library;

import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

import 'package:arxa_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:arxa_kit_showcase_app/enums/showcase_notes_enums/enums.dart';
import 'package:arxa_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';

class ShowcaseNotesFolderViewModel extends ArxaKitViewModel {
  // ── Setup ──────────────────────────────────────────────────────────────────

  ShowcaseNotesFolderViewModel({required this.folderKey});

  final String folderKey;
  final _service = arxaKitLocator<ShowcaseNotesFacadeService>();

  // ── Initial state ─────────────────────────────────────────────────────────

  /// The route's `:id` param, parsed once — the scope checks and the folder
  /// listing query switch on this, never on the raw string.
  late final ShowcaseFolderScope scope = ShowcaseFolderScope.parse(folderKey);

  bool get isTrash => scope is ShowcaseFolderScopeTrash;
  bool get isAll => scope is ShowcaseFolderScopeAll;

  // ── Streams ─────────────────────────────────────────────────────────

  /// [1. Browse notes] Owner-scoped folders; empty while signed out.
  Stream<List<ShowcaseNoteFolderModel>> get folders$ =>
      _service.session$.switchMap(
        (s) => s == null
            ? Stream<List<ShowcaseNoteFolderModel>>.value(const [])
            : _service.folders$(s.user.id),
      );

  /// [1. Browse notes] The scope's notes — trash scope, or live notes for the
  /// folder ('all' = unscoped). Empty while signed out.
  Stream<List<ShowcaseNoteModel>> get notes$ => _service.session$.switchMap(
        (s) => s == null
            ? Stream<List<ShowcaseNoteModel>>.value(const [])
            : switch (scope) {
                ShowcaseFolderScopeTrash() => _service.trash$(s.user.id),
                ShowcaseFolderScopeAll() => _service.notesIn$(s.user.id),
                ShowcaseFolderScopeFolder(:final folderId) =>
                  _service.notesIn$(s.user.id, folderId: folderId),
              },
      );

  /// UI-owned search text — seeded so [groups$] has both inputs from the
  /// first subscription.
  final BehaviorSubject<String> _query = BehaviorSubject<String>.seeded('');
  ValueStream<String> get query$ => _query.stream;

  /// [1. Browse notes] App-bar title: static for the 'all'/'trash' scopes; a
  /// live folder-name lookup otherwise (a rename lands here via [folders$]).
  /// Seeded with the pre-load fallback so the bar never flashes a loading state.
  Stream<String> get title$ {
    if (isTrash) return Stream.value('Recently Deleted');
    if (isAll) return Stream.value('All Notes');
    return folders$.map((folders) {
      for (final folder in folders) {
        if (folder.id == folderKey) return folder.name;
      }
      return 'Notes';
    }).startWith('Notes');
  }

  /// [1. Browse notes] Search-filtered, sectioned groups — the search runs on
  /// the already-streamed notes, no second fetch.
  Stream<List<ShowcaseNoteGroup>> get groups$ => Rx.combineLatest2(
        notes$,
        query$,
        (List<ShowcaseNoteModel> notes, String query) {
          final needle = query.trim().toLowerCase();
          final source = needle.isEmpty
              ? notes
              : notes
                  .where((n) => n.body.toLowerCase().contains(needle))
                  .toList();
          if (isTrash) {
            final sorted = [...source]
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
            return sorted.isEmpty
                ? const <ShowcaseNoteGroup>[]
                : [ShowcaseNoteGroup('Recently Deleted', sorted)];
          }
          return ShowcaseNotesFacadeService.groupNotes(source, DateTime.now());
        },
      );

  // ── Commands ─────────────────────────────────────────
  // Commands decide when — and whether — Actions run.

  /// [6. Delete permanently] Asks first (the hub's confirm gate); on confirm
  /// Recently Deleted is purged.
  late final _confirmEmptyTrash = abxActionHub.on<Null, void>(
    ShowcaseNotesFolderOp.emptyTrash.name,
    (_) => emptyTrash(),
    confirmTitle: 'Empty Recently Deleted',
    confirmMessage: 'Notes will be permanently deleted. This cannot be undone.',
    confirmActionLabel: 'Delete All',
    confirmDestructive: true,
  );

  /// [6. Delete permanently] Asks first (the hub's confirm gate); on confirm
  /// the note is permanently deleted.
  late final _confirmDeletePermanently =
      abxActionHub.on<ShowcaseNoteModel, void>(
    ShowcaseNotesFolderOp.deletePermanently.name,
    (note) => deletePermanently(note),
    confirmTitle: 'Delete Note',
    confirmMessage: 'This note will be permanently deleted.',
    confirmActionLabel: 'Delete',
    confirmDestructive: true,
  );

  // ── Actions ──────────────────────────────────────────

  /// [1. Browse notes] Updates the search query.
  void setQuery(String value) => _query.add(value);

  /// [3. Pinning] Pins or unpins the note.
  Future<void> togglePin(ShowcaseNoteModel note) => _service.togglePin(note);

  /// [4. Trash a note] Sends the note to Recently Deleted.
  Future<void> moveToTrash(ShowcaseNoteModel note) =>
      _service.moveToTrash(note);

  /// [7. Move to folder] Moves the note into a folder.
  Future<void> moveNoteToFolder(ShowcaseNoteModel note, String folderId) =>
      _service.moveNoteToFolder(note, folderId);

  /// [5. Restore a note] Restores a trashed note.
  Future<void> restore(ShowcaseNoteModel note) => _service.restore(note);

  /// [6. Delete permanently] Deletes the note forever (no confirm gate — the
  /// caller decides; [confirmDeletePermanently] adds one).
  Future<void> deletePermanently(ShowcaseNoteModel note) =>
      _service.deletePermanently(note);

  /// [6. Delete permanently] Empties Recently Deleted (no confirm gate — the
  /// caller decides; [confirmEmptyTrash] adds one).
  Future<void> emptyTrash() async {
    final owner = _service.currentSession?.user.id;
    if (owner != null) await _service.emptyTrash(owner);
  }

  /// [6. Delete permanently] Confirm gate for emptying trash.
  Future<void> confirmEmptyTrash() => _confirmEmptyTrash.send(null);

  /// [6. Delete permanently] Confirm gate for deleting a single note forever.
  Future<void> confirmDeletePermanently(ShowcaseNoteModel note) =>
      _confirmDeletePermanently.send(note);

  /// [2. Create a note] Creates a note and returns its id for navigation
  /// (null without an owner); outside a folder the first user folder receives it.
  Future<String?> compose() async {
    final owner = _service.currentSession?.user.id;
    if (owner == null) return null;
    final folderId = switch (scope) {
      ShowcaseFolderScopeFolder(:final folderId) => folderId,
      _ => await folders$.first
          .then((folders) => folders.isEmpty ? null : folders.first.id),
    };
    if (folderId == null) return null;
    final note = await _service.createNote(owner, folderId);
    return note.id;
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _query.close();
    super.dispose();
  }
}
