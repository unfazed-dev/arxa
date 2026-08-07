import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';

/// The notes-list screen viewmodel — streams-only (house convention): all
/// state is exposed as streams and the views bind them with [AppBoxKitStreamBuilder];
/// `BaseViewModel` is a lifecycle token (creation/disposal via StackedView),
/// never a rebuild mechanism — `notifyListeners` is not called.
///
/// [folderKey] is `'all'`, `'trash'`, or a folder uuid, resolved by the view
/// from the route's `:id` path param.
///
/// Data streams are facade pass-throughs composed with rxdart `switchMap`
/// (session → owner-scoped reads), so the VM holds no relay fields and no
/// subscription bookkeeping for them — each [AppBoxKitStreamBuilder] owns its
/// subscription. While signed out the streams emit empty lists (the Folders
/// screen gates auth, so by the time this viewmodel exists a session is
/// expected to be live). The one VM-owned UI state, [query$], is a seeded
/// [BehaviorSubject].
class ShowcaseNotesFolderViewModel extends AppBoxKitViewModel {
  ShowcaseNotesFolderViewModel({required this.folderKey});

  final String folderKey;
  final _service = appBoxKitLocator<ShowcaseNotesFacadeService>();

  bool get isTrash => folderKey == 'trash';
  bool get isAll => folderKey == 'all';

  /// Owner-scoped folders; empty while signed out.
  Stream<List<ShowcaseNoteFolderModel>> get folders$ =>
      _service.session$.switchMap(
        (s) => s == null
            ? Stream<List<ShowcaseNoteFolderModel>>.value(const [])
            : _service.folders$(s.user.id),
      );

  /// The scope's notes — trash scope, or live notes for the folder ('all' =
  /// unscoped). Empty while signed out.
  Stream<List<ShowcaseNoteModel>> get notes$ => _service.session$.switchMap(
        (s) => s == null
            ? Stream<List<ShowcaseNoteModel>>.value(const [])
            : isTrash
                ? _service.trash$(s.user.id)
                : _service.notesIn$(s.user.id,
                    folderId: isAll ? null : folderKey),
      );

  /// UI-owned search text — seeded so [groups$] has both inputs from the
  /// first subscription.
  final BehaviorSubject<String> _query = BehaviorSubject<String>.seeded('');
  ValueStream<String> get query$ => _query.stream;

  /// App-bar title: static for the 'all'/'trash' scopes; a live folder-name
  /// lookup otherwise (a rename lands here via [folders$]). Seeded with the
  /// pre-load fallback so the bar never flashes a loading state.
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

  /// Search-filtered, sectioned groups. Search filters the already-streamed
  /// scope — no second stream needed (ShowcaseNotesFacadeService.search$
  /// exists for facade callers; here the notes are in hand).
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

  void setQuery(String value) => _query.add(value);

  Future<void> togglePin(ShowcaseNoteModel note) => _service.togglePin(note);
  Future<void> moveToTrash(ShowcaseNoteModel note) =>
      _service.moveToTrash(note);
  Future<void> moveNoteToFolder(ShowcaseNoteModel note, String folderId) =>
      _service.moveNoteToFolder(note, folderId);
  Future<void> restore(ShowcaseNoteModel note) => _service.restore(note);
  Future<void> deletePermanently(ShowcaseNoteModel note) =>
      _service.deletePermanently(note);

  Future<void> emptyTrash() async {
    final owner = _service.currentSession?.user.id;
    if (owner != null) await _service.emptyTrash(owner);
  }

  // ── Commands ─────────────────────────────────────────
  // Commands decide when — and whether — Actions run.

  /// Asks first (the hub's confirm gate); on confirm Recently Deleted is purged.
  late final _confirmEmptyTrash = abxActionHub.on<Null, void>(
    'emptyTrash',
    (_) => emptyTrash(),
    confirmTitle: 'Empty Recently Deleted',
    confirmMessage: 'Notes will be permanently deleted. This cannot be undone.',
    confirmActionLabel: 'Delete All',
    confirmDestructive: true,
  );

  Future<void> confirmEmptyTrash() => _confirmEmptyTrash.send(null);

  /// Asks first (the hub's confirm gate); on confirm the note is permanently deleted.
  late final _confirmDeletePermanently = abxActionHub.on<ShowcaseNoteModel, void>(
    'deletePermanently',
    (note) => deletePermanently(note),
    confirmTitle: 'Delete Note',
    confirmMessage: 'This note will be permanently deleted.',
    confirmActionLabel: 'Delete',
    confirmDestructive: true,
  );

  Future<void> confirmDeletePermanently(ShowcaseNoteModel note) =>
      _confirmDeletePermanently.send(note);

  /// Creates a note and returns its id for the caller to navigate to, or
  /// `null` if there's no owner / no folder to place it in. From 'all' or
  /// 'trash' the first user folder is the compose target (there is no natural
  /// folder to write into there).
  Future<String?> compose() async {
    final owner = _service.currentSession?.user.id;
    if (owner == null) return null;
    final folderId = isAll || isTrash
        ? await folders$.first
            .then((folders) => folders.isEmpty ? null : folders.first.id)
        : folderKey;
    if (folderId == null) return null;
    final note = await _service.createNote(owner, folderId);
    return note.id;
  }

  @override
  void dispose() {
    _query.close();
    super.dispose();
  }
}
