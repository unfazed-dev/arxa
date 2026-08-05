import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:appbox_kit_core/kit_locator.dart';

import 'package:appbox_kit_showcase_app/models/showcase_note.dart';
import 'package:appbox_kit_showcase_app/models/showcase_note_folder.dart';
import 'package:appbox_kit_showcase_app/services/facades/showcase_notes_facade.dart';

/// The notes-list screen viewmodel. [folderKey] is `'all'`, `'trash'`, or a
/// folder uuid, resolved by the view from the route's `:id` path param.
///
/// Owner comes from [ShowcaseNotesFacade.currentSession] at construction time — the
/// Folders screen gates auth, so by the time this viewmodel exists a session
/// is expected to be live; if not, the streams simply never start and the
/// view renders nothing (matches the folders screen's gate contract).
class ShowcaseNotesFolderViewModel extends BaseViewModel {
  ShowcaseNotesFolderViewModel({required this.folderKey}) {
    final owner = _service.currentSession?.user.id;
    if (owner == null) return;

    _foldersSub = _service.folders$(owner).listen((folders) {
      _folders = folders;
      notifyListeners();
    });

    _notesSub = (isTrash
            ? _service.trash$(owner)
            : _service.notesIn$(owner, folderId: isAll ? null : folderKey))
        .listen((notes) {
      _notes = notes;
      notifyListeners();
    });
  }

  final String folderKey;
  final _service = locator<ShowcaseNotesFacade>();

  StreamSubscription<List<ShowcaseNote>>? _notesSub;
  StreamSubscription<List<ShowcaseNoteFolder>>? _foldersSub;

  List<ShowcaseNote> _notes = const [];
  List<ShowcaseNoteFolder> _folders = const [];

  String query = '';

  bool get isTrash => folderKey == 'trash';
  bool get isAll => folderKey == 'all';

  String get title {
    if (isTrash) return 'Recently Deleted';
    if (isAll) return 'All Notes';
    for (final folder in _folders) {
      if (folder.id == folderKey) return folder.name;
    }
    return 'Notes';
  }

  /// The first user folder, used as the compose target when creating a note
  /// from 'all' or 'trash' (there is no natural folder to write into there).
  ShowcaseNoteFolder? get _firstFolder => _folders.isEmpty ? null : _folders.first;

  List<ShowcaseNoteGroup> get groups {
    // Search filters the already-held scope — no second stream needed
    // (ShowcaseNotesFacade.search$ exists for facade callers; here the notes are
    // in hand).
    final needle = query.trim().toLowerCase();
    final source = needle.isEmpty
        ? _notes
        : _notes.where((n) => n.body.toLowerCase().contains(needle)).toList();
    if (isTrash) {
      final sorted = [...source]
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return sorted.isEmpty
          ? const []
          : [ShowcaseNoteGroup('Recently Deleted', sorted)];
    }
    return ShowcaseNotesFacade.groupNotes(source, DateTime.now());
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  Future<void> togglePin(ShowcaseNote note) => _service.togglePin(note);
  Future<void> moveToTrash(ShowcaseNote note) => _service.moveToTrash(note);
  Future<void> restore(ShowcaseNote note) => _service.restore(note);
  Future<void> deletePermanently(ShowcaseNote note) => _service.deletePermanently(note);

  Future<void> emptyTrash() async {
    final owner = _service.currentSession?.user.id;
    if (owner != null) await _service.emptyTrash(owner);
  }

  /// Creates a note and returns its id for the caller to navigate to, or
  /// `null` if there's no owner / no folder to place it in.
  Future<String?> compose() async {
    final owner = _service.currentSession?.user.id;
    if (owner == null) return null;
    final folderId = isAll || isTrash ? _firstFolder?.id : folderKey;
    if (folderId == null) return null;
    final note = await _service.createNote(owner, folderId);
    return note.id;
  }

  @override
  void dispose() {
    _notesSub?.cancel();
    _foldersSub?.cancel();
    super.dispose();
  }
}
