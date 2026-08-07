/// The notes facade — the only service layer the viewmodels talk to. Reads
/// and writes flow through the repository; this layer adds the derived,
/// UI-facing composition (counts, sectioning, search), owns every multi-
/// service transaction (attach/detach/purge move the note row AND its files
/// together), and routes every mutation through [mutate] so writes inherit
/// the kit's action automation.
///
/// This is the front door for notes and folders. It manages the note list and
/// folder tree, handles photos and voice recordings, supports text search, and
/// provides a Recently Deleted trash with permanent purge.
///
/// Requirements:
/// 1. [Create notes] — notes.note-crud.create-a-note
/// Creates and persists a new note in a folder.
/// 2. [Save note text] — notes.note-crud.edit-a-note
/// Updates the body of an existing note.
/// 3. [Delete permanently] — notes.note-crud.delete-a-note-forever
/// Purges a note and its attachment files for good.
/// 4. [Pin/unpin] — notes.pin-notes.pin-a-note-to-the-top-of-the-inbox / notes.pin-notes.unpin-a-pinned-note
/// Toggles a note's pinned state.
/// 5. [Trash/restore] — notes.trash-and-restore.trash-a-note / notes.trash-and-restore.restore-a-trashed-note
/// Moves a note to Recently Deleted, or brings it back.
/// 6. [Create folder] — notes.folders.create-a-folder
/// Makes a new folder for organizing notes.
/// 7. [Move note to folder] — notes.folders.move-a-note-into-a-folder
/// Refiles a live note into another folder.
/// 8. [Browse folder notes] — notes.folders.browse-the-notes-in-a-folder
/// Lists the live notes within a folder.
/// 9. [Attach photo] — search-and-attachments.media-attachments.attach-a-photo-to-a-note
/// Picks or captures a photo and attaches it to a note.
/// 10. [Attach voice recording] — search-and-attachments.media-attachments.attach-an-audio-recording-to-a-note
/// Stops the in-progress recording and attaches the voice note.
/// 11. [Play back audio] — search-and-attachments.media-attachments.play-back-an-audio-attachment
/// Plays and pauses an audio attachment with live progress.
/// 12. [Search notes] — search-and-attachments.search.search-notes-by-text
/// Filters live notes by case-insensitive body search.
/// 13. [Open from search] — search-and-attachments.search.open-a-note-from-a-search-result
/// Surfaces a single note by id for the editor to open.
/// 14. [Sign out]
/// Ends the current session.
/// 15. [Admin overview]
/// Shows every folder with live note counts for admin eyes.
///
/// Relationships:
///
///         ┌────────────────────────┐
///         │    notes viewmodels    │
///         └────────────────────────┘
///         ACT ▼              ▲ STRM
///         [1-15]             [1-13]
///         ┌────────────────────────┐
///         │      notes facade      │
///         └────────────────────────┘
///         ACT ▼              ▲ STRM
///         [1-16]             [1-5]
///     ┌────────────┐   ┌───────────────┐
///     │ repository │   │ media adapter │
///     └────────────┘   └───────────────┘
///         ════════ abxAction ════════
///
///  streams (STRM)              actions (ACT)               commands (CMD)
///    1. session$                 1. createNote               1. create
///    2. overview$                2. saveBody                 2. save
///    3. adminOverview$           3. togglePin                3. pin
///    4. notesIn$                 4. addAttachment            4. attach
///    5. trash$                   5. addPhoto                 5. detach
///    6. note$                    6. addVoiceNote             6. trash
///    7. recording$               7. removeAttachment         7. restore
///    8. playingAttachmentId$     8. moveToTrash              8. move
///    9. playerState$             9. restore                  9. purge
///   10. isAttachmentPlaying$    10. moveNoteToFolder        10. emptyTrash
///   11. playbackProgress$       11. deletePermanently       11. folderCreate
///   12. search$                 12. emptyTrash              12. folderRename
///   13. folders$                13. createFolder            13. folderDelete
///                              14. renameFolder            14. signOut
///                              15. deleteFolder
///                              16. signOut
///
///
/// History: git log --follow -- kit/showcase_app/lib/services/showcase_notes_services/facades/showcase_notes_facade_service.dart
library;

import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:appbox_kit_media/appbox_kit_media.dart'
    show AppBoxKitPlaybackProgress, AppBoxKitPlaybackState;
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart'
    show appBoxKitLocator, Rx, ValueStream;

import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:appbox_kit_showcase_app/enums/showcase_notes_enums/enums.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/repositories/showcase_notes_repository_service.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/adapters/showcase_notes_media_adapter_service.dart';

class ShowcaseNotesFacadeService extends AppBoxKitDataFacade {
  // ── Setup ──────────────────────────────────────────────────────────────────

  ShowcaseNotesRepositoryService get _repo => appBoxKitLocator<ShowcaseNotesRepositoryService>();
  ShowcaseNotesMediaAdapterService get _media => appBoxKitLocator<ShowcaseNotesMediaAdapterService>();

  Stream<AppBoxKitAuthSession?> get session$ => auth.session$;
  AppBoxKitAuthSession? get currentSession => auth.currentSession;

  /// Whether the signed-in user carries the admin role in its seed metadata.
  bool get isAdmin => isAdminSession(currentSession);

  /// Role check on an arbitrary session — for viewmodels reacting to
  /// [session$] events, where [currentSession] may already have moved on.
  static bool isAdminSession(AppBoxKitAuthSession? session) =>
      session?.user.metadata['role'] == 'admin';

  // ── Initial state ─────────────────────────────────────────────────────────

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

  // ── Streams ─────────────────────────────────────────────────────────

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

  /// [15. Admin overview] Every owner's folders with live note counts —
  /// deliberately **no owner filter**. Admin visibility on a fake backend is
  /// a client-side showcase of role metadata; there is no security boundary
  /// to enforce, and the doc on [ShowcaseNotesAdminOverview] says so. Callers
  /// gate on [isAdmin] / [isAdminSession].
  Stream<ShowcaseNotesAdminOverview> adminOverview$() => Rx.combineLatest2(
        _repo.allFolders(),
        _repo.allNotes(),
        (List<ShowcaseNoteFolderModel> folders, List<ShowcaseNoteModel> notes) {
          final counts = <String, int>{};
          for (final note in notes.where((note) => !note.isDeleted)) {
            counts[note.folderId] = (counts[note.folderId] ?? 0) + 1;
          }
          return ShowcaseNotesAdminOverview(folders: folders, liveCountByFolder: counts);
        },
      );

  /// [8. Browse folder notes] Live notes, optionally scoped to a folder
  /// (null = All Notes).
  Stream<List<ShowcaseNoteModel>> notesIn$(String owner, {String? folderId}) =>
      _allNotes$(owner).map((notes) => notes
          .where((note) =>
              !note.isDeleted && (folderId == null || note.folderId == folderId))
          .toList());

  Stream<List<ShowcaseNoteModel>> trash$(String owner) => _allNotes$(owner)
      .map((notes) => notes.where((note) => note.isDeleted).toList());

  /// [13. Open from search] The single note behind an id — empty once deleted.
  Stream<ShowcaseNoteModel?> note$(String id) => _repo.watchNote(id);

  /// [12. Search notes] Case-insensitive body search over live notes —
  /// client-side by design (the query surface is eq/gt/lt only; text search
  /// is facade work).
  Stream<List<ShowcaseNoteModel>> search$(String owner, String query) {
    final needle = query.trim().toLowerCase();
    return notesIn$(owner).map((notes) => needle.isEmpty
        ? notes
        : notes.where((note) => note.body.toLowerCase().contains(needle)).toList());
  }

  // Adapter pass-throughs — viewmodels never import the adapter.

  bool get isCameraAvailable => _media.isCameraAvailable;

  /// [10. Attach voice recording] How long the current recording has run.
  ValueStream<Duration?> get recording$ => _media.recording$;

  /// [11. Play back audio] Which attachment is loaded in the player, if any.
  ValueStream<String?> get playingAttachmentId$ => _media.playingAttachmentId$;

  /// [11. Play back audio] Whether the player is playing, paused, or loading.
  Stream<AppBoxKitPlaybackState> get playerState$ => _media.playerState$;

  /// [11. Play back audio] Whether this attachment is the one playing right now.
  Stream<bool> isAttachmentPlaying$(String attachmentId) =>
      _media.isAttachmentPlaying$(attachmentId);

  /// [11. Play back audio] Live progress for the audio scrubber.
  Stream<AppBoxKitPlaybackProgress> get playbackProgress$ =>
      _media.playbackProgress$;

  /// [10. Attach voice recording] Starts recording; false if permission denied.
  Future<bool> startRecording() => _media.startRecording();

  Future<void> cancelRecording() => _media.cancelRecording();

  /// [11. Play back audio] Plays or pauses an audio attachment.
  Future<void> togglePlayback(ShowcaseNoteAttachmentModel attachment) =>
      _media.togglePlayback(attachment);

  /// [11. Play back audio] Where an attachment's file lives on disk.
  Future<String> resolvePath(ShowcaseNoteAttachmentModel attachment) =>
      _media.resolvePath(attachment);

  // ── Writes ──────────────────────────────────────────────────────────────────
  //
  // Notification policy (appbox convention): every chain shows an error
  // snackbar; destructive chains also confirm with a success snackbar.
  // Ops carry the entity id, so AppBoxKitAction's re-entry guard only ever
  // drops a genuine same-op double-fire — never a concurrent op on another
  // entity. Value-returning chains rethrow after the snackbar (callers await
  // the value); void chains swallow post-snackbar via completeOnError.

  /// Every mutation's hub key + snackbar copy lives on [ShowcaseNotesFacadeOp];
  /// this just forwards the op's fields into [mutate].
  Future<T> _mutateOp<T>(Future<T> Function() operation, ShowcaseNotesFacadeOp op,
          {String? entity, String? fallback}) =>
      mutate<T>(
        operation,
        name: op.name,
        entity: entity,
        error: op.error,
        success: op.success,
        fallback: fallback,
      );

  /// [1. Create notes] Creates and persists a new note in the given folder.
  Future<ShowcaseNoteModel> createNote(String owner, String folderId) => _mutateOp<ShowcaseNoteModel>(
        () => _repo.upsertNote(_repo.newNote(owner, folderId)),
        ShowcaseNotesFacadeOp.create,
      );

  /// [2. Save note text] Updates the note's body and timestamp.
  Future<ShowcaseNoteModel> saveBody(ShowcaseNoteModel note, String body) => _mutateOp<ShowcaseNoteModel>(
        () => _repo.patchNote(
          note,
          note.copyWith(body: body, updatedAt: DateTime.now().toUtc()),
        ),
        ShowcaseNotesFacadeOp.save,
        entity: note.id,
      );

  /// [4. Pin/unpin] Toggles the note's pinned state.
  Future<ShowcaseNoteModel> togglePin(ShowcaseNoteModel note) => _mutateOp<ShowcaseNoteModel>(
        () => _repo.patchNote(note, note.copyWith(pinned: !note.pinned)),
        ShowcaseNotesFacadeOp.pin,
        entity: note.id,
      );

  Future<ShowcaseNoteModel> addAttachment(ShowcaseNoteModel note, ShowcaseNoteAttachmentModel attachment) =>
      _mutateOp<ShowcaseNoteModel>(
        () => _repo.patchNote(
          note,
          note.copyWith(
            attachments: [...note.attachments, attachment],
            updatedAt: DateTime.now().toUtc(),
          ),
        ),
        ShowcaseNotesFacadeOp.attach,
        entity: note.id,
      );

  /// [9. Attach photo] Picks (or captures) a photo and attaches it — one
  /// transaction, so no caller can pick without attaching or attach without
  /// the file move. Returns the updated note; the unchanged note when the
  /// picker is cancelled.
  Future<ShowcaseNoteModel> addPhoto(ShowcaseNoteModel note, {required bool fromCamera}) async {
    final attachment = await _media.pickPhoto(fromCamera: fromCamera);
    if (attachment == null) return note;
    return addAttachment(note, attachment);
  }

  /// [10. Attach voice recording] Stops the in-progress recording and
  /// attaches the voice note — one transaction. Returns the updated note;
  /// the unchanged note when there was no recording to stop.
  Future<ShowcaseNoteModel> addVoiceNote(ShowcaseNoteModel note) async {
    final attachment = await _media.stopRecording();
    if (attachment == null) return note;
    return addAttachment(note, attachment);
  }

  /// Removes an attachment: the note row loses the reference FIRST, then the
  /// file is deleted — a crash mid-way leaves an orphan file on disk, never a
  /// dangling reference on the note.
  Future<ShowcaseNoteModel> removeAttachment(ShowcaseNoteModel note, ShowcaseNoteAttachmentModel attachment) async {
    final updated = await _mutateOp<ShowcaseNoteModel>(
      () => _repo.patchNote(
        note,
        note.copyWith(
          attachments:
              note.attachments.where((a) => a.id != attachment.id).toList(),
          updatedAt: DateTime.now().toUtc(),
        ),
      ),
      ShowcaseNotesFacadeOp.detach,
      entity: note.id,
    );
    await _media.deleteFile(attachment);
    return updated;
  }

  /// [5. Trash/restore] Sends the note to Recently Deleted.
  Future<ShowcaseNoteModel> moveToTrash(ShowcaseNoteModel note) => _mutateOp<ShowcaseNoteModel>(
        () => _repo.patchNote(
          note,
          note.copyWith(
            deletedAt: () => DateTime.now().toUtc(),
            pinned: false,
          ),
        ),
        ShowcaseNotesFacadeOp.trash,
        entity: note.id,
      );

  /// [5. Trash/restore] Brings the note back from Recently Deleted.
  Future<ShowcaseNoteModel> restore(ShowcaseNoteModel note) => _mutateOp<ShowcaseNoteModel>(
        () => _repo.patchNote(note, note.copyWith(deletedAt: () => null)),
        ShowcaseNotesFacadeOp.restore,
        entity: note.id,
      );

  /// [7. Move note to folder] Refiles a live note into another folder.
  /// No-ops (returning the note untouched, no repository write) while signed
  /// out, when the note is already in [folderId], and for trashed notes —
  /// trash/restore never touch folderId (restore returns a note to the folder
  /// it was trashed from), so folder moves stay a live-notes affair. Like
  /// trash/restore, a move does not bump updatedAt: iOS does not re-date a
  /// note on refile. Not destructive, so error snackbar only (see the policy
  /// note above).
  Future<ShowcaseNoteModel> moveNoteToFolder(ShowcaseNoteModel note, String folderId) {
    if (currentSession == null || note.folderId == folderId || note.isDeleted) {
      return Future.value(note);
    }
    return _mutateOp<ShowcaseNoteModel>(
      () => _repo.patchNote(note, note.copyWith(folderId: folderId)),
      ShowcaseNotesFacadeOp.move,
      entity: note.id,
    );
  }

  /// [3. Delete permanently] Purges a note: the row goes first, then its
  /// attachment files — a crash mid-way leaves orphan files (sweep-able),
  /// never a note with dangling references. Trashing keeps files; only purge
  /// paths delete them.
  Future<void> deletePermanently(ShowcaseNoteModel note) => _mutateOp<void>(
        () async {
          await _repo.deleteNote(note.id);
          for (final attachment in note.attachments) {
            await _media.deleteFile(attachment);
          }
        },
        ShowcaseNotesFacadeOp.purge,
        entity: note.id,
        fallback: 'Delete failed',
      );

  /// [3. Delete permanently] Permanently removes every trashed note and its
  /// attachment files.
  Future<void> emptyTrash(String owner) => _mutateOp<void>(
        () async {
          final all = await _repo.notesOf(owner);
          final trashed = all.where((note) => note.isDeleted).toList();
          for (final note in trashed) {
            await _repo.deleteNote(note.id);
          }
          for (final note in trashed) {
            for (final attachment in note.attachments) {
              await _media.deleteFile(attachment);
            }
          }
        },
        ShowcaseNotesFacadeOp.emptyTrash,
        fallback: 'Empty trash failed',
      );

  /// [6. Create folder] Makes a new folder for organizing notes.
  Future<ShowcaseNoteFolderModel> createFolder(String owner, String name,
          {required int sortOrder}) =>
      _mutateOp<ShowcaseNoteFolderModel>(
        () =>
            _repo.upsertFolder(_repo.newFolder(owner, name, sortOrder: sortOrder)),
        ShowcaseNotesFacadeOp.folderCreate,
      );

  Future<ShowcaseNoteFolderModel> renameFolder(ShowcaseNoteFolderModel folder, String name) =>
      _mutateOp<ShowcaseNoteFolderModel>(
        () => _repo.patchFolder(folder, folder.copyWith(name: name)),
        ShowcaseNotesFacadeOp.folderRename,
        entity: folder.id,
      );

  /// iOS behavior: deleting a folder sends its live notes to Recently
  /// Deleted, then removes the folder row.
  Future<void> deleteFolder(ShowcaseNoteFolderModel folder) => _mutateOp<void>(
        () async {
          final notes = await _repo.notesInFolder(folder.id);
          final now = DateTime.now().toUtc();
          for (final note in notes.where((note) => !note.isDeleted)) {
            await _repo.patchNote(
                note, note.copyWith(deletedAt: () => now, pinned: false));
          }
          await _repo.deleteFolder(folder.id);
        },
        ShowcaseNotesFacadeOp.folderDelete,
        entity: folder.id,
        fallback: 'Delete folder failed',
      );

  /// [14. Sign out] Ends the current session.
  Future<void> signOut() => abxActionHub.send<void>(
        ShowcaseNotesFacadeOp.signOut.name,
        () => auth.signOut(),
        errorNotification: ShowcaseNotesFacadeOp.signOut.error,
        errorMessage: 'Sign-out failed',
      );

  // ── Reads ───────────────────────────────────────────────────────────────────

  /// iOS Notes sectioning: Pinned first, then Today / Yesterday / Previous 7
  /// Days / Previous 30 Days / month names (current year) / year buckets.
  /// Pure and static so tests can pin `now`.
  static List<ShowcaseNoteGroup> groupNotes(List<ShowcaseNoteModel> notes, DateTime now) {
    final pinned = notes.where((note) => note.pinned).toList();
    final rest = notes.where((note) => !note.pinned).toList();

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
}
