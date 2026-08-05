import 'package:rxdart/rxdart.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:ui_library/ui_library.dart' show locator;

import 'package:appbox_kit_showcase_app/models/showcase_note.dart';
import 'package:appbox_kit_showcase_app/models/showcase_note_attachment.dart';
import 'package:appbox_kit_showcase_app/models/showcase_note_folder.dart';
import 'package:appbox_kit_showcase_app/services/repositories/showcase_notes_repository.dart';

/// Everything the folders screen needs, derived from two repository streams.
/// Counts are facade work — never query work (swap rule 2).
class ShowcaseNotesOverview {
  final List<ShowcaseNoteFolder> folders;
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
  final List<ShowcaseNoteFolder> folders;
  final Map<String, int> liveCountByFolder;

  const ShowcaseNotesAdminOverview({
    required this.folders,
    required this.liveCountByFolder,
  });
}

/// One section of the notes list ("Pinned", "Today", "Previous 7 Days", …).
class ShowcaseNoteGroup {
  final String label;
  final List<ShowcaseNote> notes;

  const ShowcaseNoteGroup(this.label, this.notes);
}

/// Facade over [ShowcaseNotesRepository] — the only layer the Notes viewmodels talk to.
/// Reads and writes flow through the repository; this layer adds the derived,
/// UI-facing composition (counts, sectioning, search) and routes every mutation
/// through [mutate] so writes inherit the kit's action automation. Streams are
/// per-owner (auth-gated app).
class ShowcaseNotesFacade extends KitDataFacade {
  ShowcaseNotesRepository get _repo => locator<ShowcaseNotesRepository>();

  Stream<KitAuthSession?> get session$ => auth.session$;
  KitAuthSession? get currentSession => auth.currentSession;

  /// Whether the signed-in user carries the admin role in its seed metadata.
  bool get isAdmin => isAdminSession(currentSession);

  /// Role check on an arbitrary session — for viewmodels reacting to
  /// [session$] events, where [currentSession] may already have moved on.
  static bool isAdminSession(KitAuthSession? session) =>
      session?.user.metadata['role'] == 'admin';

  // -- Reads (composition over repository streams) ---------------------------

  Stream<List<ShowcaseNoteFolder>> folders$(String owner) => _repo.foldersOf(owner);

  Stream<List<ShowcaseNote>> _allNotes$(String owner) => _repo.allNotesOf(owner);

  Stream<ShowcaseNotesOverview> overview$(String owner) => Rx.combineLatest2(
        folders$(owner),
        _allNotes$(owner),
        (List<ShowcaseNoteFolder> folders, List<ShowcaseNote> notes) {
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
        (List<ShowcaseNoteFolder> folders, List<ShowcaseNote> notes) {
          final counts = <String, int>{};
          for (final note in notes.where((n) => !n.isDeleted)) {
            counts[note.folderId] = (counts[note.folderId] ?? 0) + 1;
          }
          return ShowcaseNotesAdminOverview(folders: folders, liveCountByFolder: counts);
        },
      );

  /// Live notes, optionally scoped to a folder (null = All Notes).
  Stream<List<ShowcaseNote>> notesIn$(String owner, {String? folderId}) =>
      _allNotes$(owner).map((notes) => notes
          .where((n) =>
              !n.isDeleted && (folderId == null || n.folderId == folderId))
          .toList());

  Stream<List<ShowcaseNote>> trash$(String owner) => _allNotes$(owner)
      .map((notes) => notes.where((n) => n.isDeleted).toList());

  Stream<ShowcaseNote?> note$(String id) => _repo.watchNote(id);

  /// Case-insensitive body search over live notes — client-side by design
  /// (the query surface is eq/gt/lt only; text search is facade work).
  Stream<List<ShowcaseNote>> search$(String owner, String query) {
    final needle = query.trim().toLowerCase();
    return notesIn$(owner).map((notes) => needle.isEmpty
        ? notes
        : notes.where((n) => n.body.toLowerCase().contains(needle)).toList());
  }

  /// iOS Notes sectioning: Pinned first, then Today / Yesterday / Previous 7
  /// Days / Previous 30 Days / month names (current year) / year buckets.
  /// Pure and static so tests can pin `now`.
  static List<ShowcaseNoteGroup> groupNotes(List<ShowcaseNote> notes, DateTime now) {
    final pinned = notes.where((n) => n.pinned).toList();
    final rest = notes.where((n) => !n.pinned).toList();

    final today = DateTime(now.year, now.month, now.day);
    final buckets = <String, List<ShowcaseNote>>{};
    final order = <String>[];

    void add(String label, ShowcaseNote note) {
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

  Future<ShowcaseNote> createNote(String owner, String folderId) => mutate<ShowcaseNote>(
        operation: () => _repo.upsertNote(_repo.newNote(owner, folderId)),
        widgetId: 'notes.create',
      ).execute();

  Future<ShowcaseNote> saveBody(ShowcaseNote note, String body) => mutate<ShowcaseNote>(
        operation: () => _repo.upsertNote(
          note.copyWith(body: body, updatedAt: DateTime.now().toUtc()),
        ),
        widgetId: 'notes.save',
      ).execute();

  Future<ShowcaseNote> togglePin(ShowcaseNote note) => mutate<ShowcaseNote>(
        operation: () => _repo.upsertNote(note.copyWith(pinned: !note.pinned)),
        widgetId: 'notes.pin',
      ).execute();

  Future<ShowcaseNote> addAttachment(ShowcaseNote note, ShowcaseNoteAttachment attachment) =>
      mutate<ShowcaseNote>(
        operation: () => _repo.upsertNote(note.copyWith(
          attachments: [...note.attachments, attachment],
          updatedAt: DateTime.now().toUtc(),
        )),
        widgetId: 'notes.attach',
      ).execute();

  Future<ShowcaseNote> removeAttachment(ShowcaseNote note, String attachmentId) => mutate<ShowcaseNote>(
        operation: () => _repo.upsertNote(note.copyWith(
          attachments:
              note.attachments.where((a) => a.id != attachmentId).toList(),
          updatedAt: DateTime.now().toUtc(),
        )),
        widgetId: 'notes.detach',
      ).execute();

  Future<ShowcaseNote> moveToTrash(ShowcaseNote note) => mutate<ShowcaseNote>(
        operation: () => _repo.upsertNote(note.copyWith(
          deletedAt: () => DateTime.now().toUtc(),
          pinned: false,
        )),
        widgetId: 'notes.trash',
      ).execute();

  Future<ShowcaseNote> restore(ShowcaseNote note) => mutate<ShowcaseNote>(
        operation: () => _repo.upsertNote(note.copyWith(deletedAt: () => null)),
        widgetId: 'notes.restore',
      ).execute();

  Future<void> deletePermanently(ShowcaseNote note) => mutate<void>(
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

  Future<ShowcaseNoteFolder> createFolder(String owner, String name,
          {required int sortOrder}) =>
      mutate<ShowcaseNoteFolder>(
        operation: () =>
            _repo.upsertFolder(_repo.newFolder(owner, name, sortOrder: sortOrder)),
        widgetId: 'notes.folder.create',
      ).execute();

  Future<ShowcaseNoteFolder> renameFolder(ShowcaseNoteFolder folder, String name) =>
      mutate<ShowcaseNoteFolder>(
        operation: () => _repo.upsertFolder(folder.copyWith(name: name)),
        widgetId: 'notes.folder.rename',
      ).execute();

  /// iOS behavior: deleting a folder sends its live notes to Recently
  /// Deleted, then removes the folder row.
  Future<void> deleteFolder(ShowcaseNoteFolder folder) => mutate<void>(
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
