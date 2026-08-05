import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:appbox_kit_core/kit_locator.dart';

import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_model.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_folder_model.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';

/// The notes-list screen viewmodel. [folderKey] is `'all'`, `'trash'`, or a
/// folder uuid, resolved by the view from the route's `:id` path param.
///
/// Owner comes from [ShowcaseNotesFacadeService.currentSession] at construction time — the
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
  final _service = locator<ShowcaseNotesFacadeService>();

  StreamSubscription<List<ShowcaseNoteModel>>? _notesSub;
  StreamSubscription<List<ShowcaseNoteFolderModel>>? _foldersSub;

  List<ShowcaseNoteModel> _notes = const [];
  List<ShowcaseNoteFolderModel> _folders = const [];

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
  ShowcaseNoteFolderModel? get _firstFolder => _folders.isEmpty ? null : _folders.first;

  List<ShowcaseNoteGroup> get groups {
    // Search filters the already-held scope — no second stream needed
    // (ShowcaseNotesFacadeService.search$ exists for facade callers; here the notes are
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
    return ShowcaseNotesFacadeService.groupNotes(source, DateTime.now());
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  Future<void> togglePin(ShowcaseNoteModel note) => _service.togglePin(note);
  Future<void> moveToTrash(ShowcaseNoteModel note) => _service.moveToTrash(note);
  Future<void> restore(ShowcaseNoteModel note) => _service.restore(note);
  Future<void> deletePermanently(ShowcaseNoteModel note) => _service.deletePermanently(note);

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
