import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:appbox_kit_media/appbox_kit_media.dart'
    show AppBoxKitPlaybackProgress, AppBoxKitPlaybackState;
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart'
    show appBoxKitLocator, Rx, ValueStream;

import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/repositories/showcase_notes_repository_service.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/adapters/showcase_notes_media_adapter_service.dart';

/// Facade over [ShowcaseNotesRepositoryService] and [ShowcaseNotesMediaAdapterService] —
/// the only layer the Notes viewmodels talk to: note state AND the media
/// surface (recording/playback streams and actions re-exposed below).
/// Reads and writes flow through the repository; this layer adds the derived,
/// UI-facing composition (counts, sectioning, search), owns every multi-service
/// transaction (attach/detach/purge move note row AND files together), and
/// routes every mutation through [mutate] so writes inherit the kit's action
/// automation. Streams are per-owner (auth-gated app).
class ShowcaseNotesFacadeService extends AppBoxKitDataFacade {
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
          for (final note in notes.where((note) => !note.isDeleted)) {
            counts[note.folderId] = (counts[note.folderId] ?? 0) + 1;
          }
          return ShowcaseNotesAdminOverview(folders: folders, liveCountByFolder: counts);
        },
      );

  /// Live notes, optionally scoped to a folder (null = All Notes).
  Stream<List<ShowcaseNoteModel>> notesIn$(String owner, {String? folderId}) =>
      _allNotes$(owner).map((notes) => notes
          .where((note) =>
              !note.isDeleted && (folderId == null || note.folderId == folderId))
          .toList());

  Stream<List<ShowcaseNoteModel>> trash$(String owner) => _allNotes$(owner)
      .map((notes) => notes.where((note) => note.isDeleted).toList());

  Stream<ShowcaseNoteModel?> note$(String id) => _repo.watchNote(id);

  // -- Media (adapter pass-throughs — viewmodels never import the adapter) ----

  bool get isCameraAvailable => _media.isCameraAvailable;

  ValueStream<Duration?> get recording$ => _media.recording$;

  ValueStream<String?> get playingAttachmentId$ => _media.playingAttachmentId$;

  Stream<AppBoxKitPlaybackState> get playerState$ => _media.playerState$;

  Stream<bool> isAttachmentPlaying$(String attachmentId) =>
      _media.isAttachmentPlaying$(attachmentId);

  Stream<AppBoxKitPlaybackProgress> get playbackProgress$ =>
      _media.playbackProgress$;

  Future<bool> startRecording() => _media.startRecording();

  Future<void> cancelRecording() => _media.cancelRecording();

  Future<void> togglePlayback(ShowcaseNoteAttachmentModel attachment) =>
      _media.togglePlayback(attachment);

  Future<String> resolvePath(ShowcaseNoteAttachmentModel attachment) =>
      _media.resolvePath(attachment);

  /// Case-insensitive body search over live notes — client-side by design
  /// (the query surface is eq/gt/lt only; text search is facade work).
  Stream<List<ShowcaseNoteModel>> search$(String owner, String query) {
    final needle = query.trim().toLowerCase();
    return notesIn$(owner).map((notes) => needle.isEmpty
        ? notes
        : notes.where((note) => note.body.toLowerCase().contains(needle)).toList());
  }

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

  // -- Mutations (all through the AppBoxKitAction chain, over repository writes) ----
  //
  // Notification policy (appbox convention): every chain shows an error
  // snackbar; destructive chains also confirm with a success snackbar.
  // Ops carry the entity id, so AppBoxKitAction's re-entry guard only ever
  // drops a genuine same-op double-fire — never a concurrent op on another
  // entity. Value-returning chains rethrow after the snackbar (callers await
  // the value); void chains swallow post-snackbar via completeOnError.

  Future<ShowcaseNoteModel> createNote(String owner, String folderId) => mutate<ShowcaseNoteModel>(
        () => _repo.upsertNote(_repo.newNote(owner, folderId)),
        name: 'create',
        error: 'Could not create note',
      );

  Future<ShowcaseNoteModel> saveBody(ShowcaseNoteModel note, String body) => mutate<ShowcaseNoteModel>(
        () => _repo.patchNote(
          note,
          note.copyWith(body: body, updatedAt: DateTime.now().toUtc()),
        ),
        name: 'save',
        entity: note.id,
        error: 'Could not save note',
      );

  Future<ShowcaseNoteModel> togglePin(ShowcaseNoteModel note) => mutate<ShowcaseNoteModel>(
        () => _repo.patchNote(note, note.copyWith(pinned: !note.pinned)),
        name: 'pin',
        entity: note.id,
        error: 'Could not update note',
      );

  Future<ShowcaseNoteModel> addAttachment(ShowcaseNoteModel note, ShowcaseNoteAttachmentModel attachment) =>
      mutate<ShowcaseNoteModel>(
        () => _repo.patchNote(
          note,
          note.copyWith(
            attachments: [...note.attachments, attachment],
            updatedAt: DateTime.now().toUtc(),
          ),
        ),
        name: 'attach',
        entity: note.id,
        error: 'Could not add attachment',
      );

  /// Picks (or captures) a photo and attaches it — one transaction, so no
  /// caller can pick without attaching or attach without the file move.
  /// Returns the updated note; the unchanged note when the picker is cancelled.
  Future<ShowcaseNoteModel> addPhoto(ShowcaseNoteModel note, {required bool fromCamera}) async {
    final attachment = await _media.pickPhoto(fromCamera: fromCamera);
    if (attachment == null) return note;
    return addAttachment(note, attachment);
  }

  /// Stops the in-progress recording and attaches the voice note — one
  /// transaction. Returns the updated note; the unchanged note when there was
  /// no recording to stop.
  Future<ShowcaseNoteModel> addVoiceNote(ShowcaseNoteModel note) async {
    final attachment = await _media.stopRecording();
    if (attachment == null) return note;
    return addAttachment(note, attachment);
  }

  /// Removes an attachment: the note row loses the reference FIRST, then the
  /// file is deleted — a crash mid-way leaves an orphan file on disk, never a
  /// dangling reference on the note.
  Future<ShowcaseNoteModel> removeAttachment(ShowcaseNoteModel note, ShowcaseNoteAttachmentModel attachment) async {
    final updated = await mutate<ShowcaseNoteModel>(
      () => _repo.patchNote(
        note,
        note.copyWith(
          attachments:
              note.attachments.where((a) => a.id != attachment.id).toList(),
          updatedAt: DateTime.now().toUtc(),
        ),
      ),
      name: 'detach',
      entity: note.id,
      error: 'Could not remove attachment',
    );
    await _media.deleteFile(attachment);
    return updated;
  }

  Future<ShowcaseNoteModel> moveToTrash(ShowcaseNoteModel note) => mutate<ShowcaseNoteModel>(
        () => _repo.patchNote(
          note,
          note.copyWith(
            deletedAt: () => DateTime.now().toUtc(),
            pinned: false,
          ),
        ),
        name: 'trash',
        entity: note.id,
        error: 'Could not move note to Recently Deleted',
        success: 'Moved to Recently Deleted',
      );

  Future<ShowcaseNoteModel> restore(ShowcaseNoteModel note) => mutate<ShowcaseNoteModel>(
        () => _repo.patchNote(note, note.copyWith(deletedAt: () => null)),
        name: 'restore',
        entity: note.id,
        error: 'Could not restore note',
      );

  /// Refiles a live note into another folder. No-ops (returning the note
  /// untouched, no repository write) while signed out, when the note is
  /// already in [folderId], and for trashed notes — trash/restore never
  /// touch folderId (restore returns a note to the folder it was trashed
  /// from), so folder moves stay a live-notes affair. Like trash/restore,
  /// a move does not bump updatedAt: iOS does not re-date a note on refile.
  /// Not destructive, so error snackbar only (see the policy note above).
  Future<ShowcaseNoteModel> moveNoteToFolder(ShowcaseNoteModel note, String folderId) {
    if (currentSession == null || note.folderId == folderId || note.isDeleted) {
      return Future.value(note);
    }
    return mutate<ShowcaseNoteModel>(
      () => _repo.patchNote(note, note.copyWith(folderId: folderId)),
      name: 'move',
      entity: note.id,
      error: 'Could not move note',
    );
  }

  /// Purges a note: the row goes first, then its attachment files — a crash
  /// mid-way leaves orphan files (sweep-able), never a note with dangling
  /// references. Trashing keeps files; only purge paths delete them.
  Future<void> deletePermanently(ShowcaseNoteModel note) => mutate<void>(
        () async {
          await _repo.deleteNote(note.id);
          for (final attachment in note.attachments) {
            await _media.deleteFile(attachment);
          }
        },
        name: 'purge',
        entity: note.id,
        error: 'Could not delete note',
        success: 'Note deleted',
        fallback: 'Delete failed',
      );

  Future<void> emptyTrash(String owner) => mutate<void>(
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
        name: 'emptyTrash',
        error: 'Could not empty Recently Deleted',
        success: 'Recently Deleted emptied',
        fallback: 'Empty trash failed',
      );

  Future<ShowcaseNoteFolderModel> createFolder(String owner, String name,
          {required int sortOrder}) =>
      mutate<ShowcaseNoteFolderModel>(
        () =>
            _repo.upsertFolder(_repo.newFolder(owner, name, sortOrder: sortOrder)),
        name: 'folder.create',
        error: 'Could not create folder',
      );

  Future<ShowcaseNoteFolderModel> renameFolder(ShowcaseNoteFolderModel folder, String name) =>
      mutate<ShowcaseNoteFolderModel>(
        () => _repo.patchFolder(folder, folder.copyWith(name: name)),
        name: 'folder.rename',
        entity: folder.id,
        error: 'Could not rename folder',
      );

  /// iOS behavior: deleting a folder sends its live notes to Recently
  /// Deleted, then removes the folder row.
  Future<void> deleteFolder(ShowcaseNoteFolderModel folder) => mutate<void>(
        () async {
          final notes = await _repo.notesInFolder(folder.id);
          final now = DateTime.now().toUtc();
          for (final note in notes.where((note) => !note.isDeleted)) {
            await _repo.patchNote(
                note, note.copyWith(deletedAt: () => now, pinned: false));
          }
          await _repo.deleteFolder(folder.id);
        },
        name: 'folder.delete',
        entity: folder.id,
        error: 'Could not delete folder',
        success: 'Folder deleted',
        fallback: 'Delete folder failed',
      );

  // -- Auth ------------------------------------------------------------------

  Future<void> signOut() => abxActionHub.send<void>(
        'signOut',
        () => auth.signOut(),
        errorNotification: 'Could not sign out',
        errorMessage: 'Sign-out failed',
      );
}
