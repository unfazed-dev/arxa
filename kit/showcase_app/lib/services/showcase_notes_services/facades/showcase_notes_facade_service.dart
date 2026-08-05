import 'package:rxdart/rxdart.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:ui_library/ui_library.dart' show locator;

import 'package:appbox_kit_showcase_app/models/showcase_notes_models/showcase_note_model.dart';
import 'package:appbox_kit_showcase_app/models/showcase_notes_models/showcase_note_attachment_model.dart';
import 'package:appbox_kit_showcase_app/models/showcase_notes_models/showcase_note_folder_model.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/repositories/showcase_notes_repository_service.dart';

/// Everything the folders screen needs, derived from two repository streams.
/// Counts are facade work — never query work (swap rule 2).
class ShowcaseNotesOverview {
  final List<ShowcaseNoteFolderModel> folders;
  final Map<String, int> liveCountByFolder;
  final int allCount;
  final int trashCount;

  const ShowcaseNotesOverview({
    required this.folders,
    required this.liveCountByFolder,
    required this.allCount,
    required this.trashCount,
  });
}

/// Everything the admin section needs: every owner's folders plus live note
/// counts, unfiltered. Showcase-only — the seed backend is fake and entirely
/// client-side, so this demonstrates role-gated *visibility*, not a security
/// boundary.
class ShowcaseNotesAdminOverview {
  final List<ShowcaseNoteFolderModel> folders;
  final Map<String, int> liveCountByFolder;

  const ShowcaseNotesAdminOverview({
    required this.folders,
    required this.liveCountByFolder,
  });
}

/// One section of the notes list ("Pinned", "Today", "Previous 7 Days", …).
class ShowcaseNoteGroup {
  final String label;
  final List<ShowcaseNoteModel> notes;

  const ShowcaseNoteGroup(this.label, this.notes);
}

/// Facade over [ShowcaseNotesRepositoryService] — the only layer the Notes viewmodels talk to.
/// Reads and writes flow through the repository; this layer adds the derived,
/// UI-facing composition (counts, sectioning, search) and routes every mutation
/// through [mutate] so writes inherit the kit's action automation. Streams are
/// per-owner (auth-gated app).
class ShowcaseNotesFacadeService extends KitDataFacade {
  ShowcaseNotesRepositoryService get _repo => locator<ShowcaseNotesRepositoryService>();

  Stream<KitAuthSession?> get session$ => auth.session$;
  KitAuthSession? get currentSession => auth.currentSession;

  /// Whether the signed-in user carries the admin role in its seed metadata.
  bool get isAdmin => isAdminSession(currentSession);

  /// Role check on an arbitrary session — for viewmodels reacting to
  /// [session$] events, where [currentSession] may already have moved on.
  static bool isAdminSession(KitAuthSession? session) =>
      session?.user.metadata['role'] == 'admin';

  // -- Reads (composition over repository streams) ---------------------------

  Stream<List<ShowcaseNoteFolderModel>> folders$(String owner) => _repo.foldersOf(owner);

  Stream<List<ShowcaseNoteModel>> _allNotes$(String owner) => _repo.allNotesOf(owner);

  Stream<ShowcaseNotesOverview> overview$(String owner) => Rx.combineLatest2(
        folders$(owner),
        _allNotes$(owner),
        (List<ShowcaseNoteFolderModel> folders, List<ShowcaseNoteModel> notes) {
          final counts = <String, int>{};
          var live = 0;
          var trash = 0;
          for (final note in notes) {
            if (note.isDeleted) {
              trash++;
            } else {
              live++;
              counts[note.folderId] = (counts[note.folderId] ?? 0) + 1;
            }
          }
          return ShowcaseNotesOverview(
            folders: folders,
            liveCountByFolder: counts,
            allCount: live,
            trashCount: trash,
          );
        },
      );

  /// Every owner's folders with live note counts — deliberately **no owner
  /// filter**. Admin visibility on a fake backend is a client-side showcase
  /// of role metadata; there is no security boundary to enforce, and the doc
  /// on [ShowcaseNotesAdminOverview] says so. Callers gate on [isAdmin] / [isAdminSession].
  Stream<ShowcaseNotesAdminOverview> adminOverview$() => Rx.combineLatest2(
        _repo.allFolders(),
        _repo.allNotes(),
        (List<ShowcaseNoteFolderModel> folders, List<ShowcaseNoteModel> notes) {
          final counts = <String, int>{};
          for (final note in notes.where((n) => !n.isDeleted)) {
            counts[note.folderId] = (counts[note.folderId] ?? 0) + 1;
          }
          return ShowcaseNotesAdminOverview(folders: folders, liveCountByFolder: counts);
        },
      );

  /// Live notes, optionally scoped to a folder (null = All Notes).
  Stream<List<ShowcaseNoteModel>> notesIn$(String owner, {String? folderId}) =>
      _allNotes$(owner).map((notes) => notes
          .where((n) =>
              !n.isDeleted && (folderId == null || n.folderId == folderId))
          .toList());

  Stream<List<ShowcaseNoteModel>> trash$(String owner) => _allNotes$(owner)
      .map((notes) => notes.where((n) => n.isDeleted).toList());

  Stream<ShowcaseNoteModel?> note$(String id) => _repo.watchNote(id);

  /// Case-insensitive body search over live notes — client-side by design
  /// (the query surface is eq/gt/lt only; text search is facade work).
  Stream<List<ShowcaseNoteModel>> search$(String owner, String query) {
    final needle = query.trim().toLowerCase();
    return notesIn$(owner).map((notes) => needle.isEmpty
        ? notes
        : notes.where((n) => n.body.toLowerCase().contains(needle)).toList());
  }

  /// iOS Notes sectioning: Pinned first, then Today / Yesterday / Previous 7
  /// Days / Previous 30 Days / month names (current year) / year buckets.
  /// Pure and static so tests can pin `now`.
  static List<ShowcaseNoteGroup> groupNotes(List<ShowcaseNoteModel> notes, DateTime now) {
    final pinned = notes.where((n) => n.pinned).toList();
    final rest = notes.where((n) => !n.pinned).toList();

    final today = DateTime(now.year, now.month, now.day);
    final buckets = <String, List<ShowcaseNoteModel>>{};
    final order = <String>[];

    void add(String label, ShowcaseNoteModel note) {
      if (!buckets.containsKey(label)) {
        buckets[label] = [];
        order.add(label);
      }
      buckets[label]!.add(note);
    }

    for (final note in rest) {
      final at = note.updatedAt.toLocal();
      final day = DateTime(at.year, at.month, at.day);
      final daysAgo = today.difference(day).inDays;
      if (daysAgo <= 0) {
        add('Today', note);
      } else if (daysAgo == 1) {
        add('Yesterday', note);
      } else if (daysAgo <= 7) {
        add('Previous 7 Days', note);
      } else if (daysAgo <= 30) {
        add('Previous 30 Days', note);
      } else if (at.year == now.year) {
        add(_monthNames[at.month - 1], note);
      } else {
        add('${at.year}', note);
      }
    }

    return [
      if (pinned.isNotEmpty) ShowcaseNoteGroup('Pinned', pinned),
      for (final label in order) ShowcaseNoteGroup(label, buckets[label]!),
    ];
  }

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  // -- Mutations (all through the KitAction chain, over repository writes) ----

  Future<ShowcaseNoteModel> createNote(String owner, String folderId) => mutate<ShowcaseNoteModel>(
        operation: () => _repo.upsertNote(_repo.newNote(owner, folderId)),
        widgetId: 'notes.create',
      ).execute();

  Future<ShowcaseNoteModel> saveBody(ShowcaseNoteModel note, String body) => mutate<ShowcaseNoteModel>(
        operation: () => _repo.upsertNote(
          note.copyWith(body: body, updatedAt: DateTime.now().toUtc()),
        ),
        widgetId: 'notes.save',
      ).execute();

  Future<ShowcaseNoteModel> togglePin(ShowcaseNoteModel note) => mutate<ShowcaseNoteModel>(
        operation: () => _repo.upsertNote(note.copyWith(pinned: !note.pinned)),
        widgetId: 'notes.pin',
      ).execute();

  Future<ShowcaseNoteModel> addAttachment(ShowcaseNoteModel note, ShowcaseNoteAttachmentModel attachment) =>
      mutate<ShowcaseNoteModel>(
        operation: () => _repo.upsertNote(note.copyWith(
          attachments: [...note.attachments, attachment],
          updatedAt: DateTime.now().toUtc(),
        )),
        widgetId: 'notes.attach',
      ).execute();

  Future<ShowcaseNoteModel> removeAttachment(ShowcaseNoteModel note, String attachmentId) => mutate<ShowcaseNoteModel>(
        operation: () => _repo.upsertNote(note.copyWith(
          attachments:
              note.attachments.where((a) => a.id != attachmentId).toList(),
          updatedAt: DateTime.now().toUtc(),
        )),
        widgetId: 'notes.detach',
      ).execute();

  Future<ShowcaseNoteModel> moveToTrash(ShowcaseNoteModel note) => mutate<ShowcaseNoteModel>(
        operation: () => _repo.upsertNote(note.copyWith(
          deletedAt: () => DateTime.now().toUtc(),
          pinned: false,
        )),
        widgetId: 'notes.trash',
      ).execute();

  Future<ShowcaseNoteModel> restore(ShowcaseNoteModel note) => mutate<ShowcaseNoteModel>(
        operation: () => _repo.upsertNote(note.copyWith(deletedAt: () => null)),
        widgetId: 'notes.restore',
      ).execute();

  Future<void> deletePermanently(ShowcaseNoteModel note) => mutate<void>(
        operation: () => _repo.deleteNote(note.id),
        widgetId: 'notes.purge',
      ).execute();

  Future<void> emptyTrash(String owner) => mutate<void>(
        operation: () async {
          final all = await _repo.notesOf(owner);
          for (final note in all.where((n) => n.isDeleted)) {
            await _repo.deleteNote(note.id);
          }
        },
        widgetId: 'notes.emptyTrash',
      ).withSuccessSnackbar('Recently Deleted emptied').execute();

  Future<ShowcaseNoteFolderModel> createFolder(String owner, String name,
          {required int sortOrder}) =>
      mutate<ShowcaseNoteFolderModel>(
        operation: () =>
            _repo.upsertFolder(_repo.newFolder(owner, name, sortOrder: sortOrder)),
        widgetId: 'notes.folder.create',
      ).execute();

  Future<ShowcaseNoteFolderModel> renameFolder(ShowcaseNoteFolderModel folder, String name) =>
      mutate<ShowcaseNoteFolderModel>(
        operation: () => _repo.upsertFolder(folder.copyWith(name: name)),
        widgetId: 'notes.folder.rename',
      ).execute();

  /// iOS behavior: deleting a folder sends its live notes to Recently
  /// Deleted, then removes the folder row.
  Future<void> deleteFolder(ShowcaseNoteFolderModel folder) => mutate<void>(
        operation: () async {
          final notes = await _repo.notesInFolder(folder.id);
          final now = DateTime.now().toUtc();
          for (final note in notes.where((n) => !n.isDeleted)) {
            await _repo
                .upsertNote(note.copyWith(deletedAt: () => now, pinned: false));
          }
          await _repo.deleteFolder(folder.id);
        },
        widgetId: 'notes.folder.delete',
      ).execute();

  // -- Auth ------------------------------------------------------------------

  Future<void> signOut() => auth.signOut();
}
