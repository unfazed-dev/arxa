/// The folders-screen viewmodel. The view calls actions in and reads streams
/// out: when the user does something, the matching action does the work; when
/// something changes, the new value flows down the stream and the view redraws
/// just the part listening to it. The viewmodel never touches the view — swap
/// the UI for any other and this file stays unchanged.
///
/// This is the business logic for the screen that lists folders. A signed-in
/// user sees their folders with note counts, creates or renames a folder from a
/// prompt, and deletes one after confirming (its notes move to Recently
/// Deleted). While signed out the screen shows the sign-in or create-account
/// panel; signing in from either swaps back to the folders list.
///
/// Requirements:
/// 1. [Create a folder] — create-a-folder
/// A folder is created with a prompted name.
///
/// Relationships:
///
///      ┌─────────────────────────┐
///      │   notes folders view    │
///      └─────────────────────────┘
///      ACT ▼               ▲ STRM
///      [1-9]               [1-4]
///   ┌───────────────────────────────┐
///   │        notes viewmodel        │
///   └───────────────────────────────┘
///            ACT ▼    ▲ STRM
///            [1-4]    [1-3]
///            ┌──────────────┐
///            │ notes facade │
///            └──────────────┘
///      ════════ abxAction ════════
///
///  streams (STRM)            actions (ACT)
///    1. session$              1. openCreateAccount
///    2. overview$             2. closeCreateAccount
///    3. adminOverview$        3. createFolder
///    4. showCreateAccount$    4. createFolderWithPrompt
///                            5. renameFolderWithPrompt
///                            6. confirmDeleteFolder
///                            7. renameFolder
///                            8. deleteFolder
///                            9. signOut
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_viewmodel.dart
library;

import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

import 'package:arxa_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:arxa_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';

class ShowcaseNotesViewModel extends ArxaKitViewModel {
  // ── Setup ──────────────────────────────────────────────────────────────────

  final _service = arxaKitLocator<ShowcaseNotesFacadeService>();

  ShowcaseNotesViewModel() {
    // VM-internal side effect (no view data): reset the panel choice when a
    // session appears. One listen, one dispose — the data streams above need
    // no subscription management here.
    listen(
      'session.resetPanel',
      to: [_service.session$],
      onData: (session) {
        if (session != null) _showCreateAccount.add(false);
      },
    );
  }

  // ── Initial state ─────────────────────────────────────────────────────────

  /// When signed out, whether the panel shows create-account instead of
  /// sign-in; reset whenever a session appears.
  final BehaviorSubject<bool> _showCreateAccount =
      BehaviorSubject<bool>.seeded(false);
  ValueStream<bool> get showCreateAccount$ => _showCreateAccount.stream;

  // ── Streams ─────────────────────────────────────────────────────────

  /// Null while signed out — the views swap to the auth surface on null.
  Stream<ArxaKitAuthSession?> get session$ => _service.session$;

  /// Owner-scoped folder overview; null while signed out.
  Stream<ShowcaseNotesOverview?> get overview$ => _service.session$.switchMap(
        (session) => session == null
            ? Stream<ShowcaseNotesOverview?>.value(null)
            : _service.overview$(session.user.id),
      );

  /// Cross-owner folders and counts; non-null only during an admin session
  /// (demo gating, not a security boundary — real apps enforce server-side).
  Stream<ShowcaseNotesAdminOverview?> get adminOverview$ =>
      _service.session$.switchMap(
        (session) => ShowcaseNotesFacadeService.isAdminSession(session)
            ? _service.adminOverview$()
            : Stream<ShowcaseNotesAdminOverview?>.value(null),
      );

  // ── Actions ──────────────────────────────────────────

  /// Swaps the signed-out panel to create-account.
  void openCreateAccount() => _showCreateAccount.add(true);

  /// Swaps the signed-out panel back to sign-in.
  void closeCreateAccount() => _showCreateAccount.add(false);

  /// [1. Create a folder] Creates a folder with the given name at the end of
  /// the current overview's sort order.
  Future<void> createFolder(String name) async {
    final owner = _service.currentSession?.user.id;
    final trimmed = name.trim();
    if (owner == null || trimmed.isEmpty) return;
    final sortOrder = await _service
        .overview$(owner)
        .first
        .then((overview) => overview.folders.length);
    await _service.createFolder(owner, trimmed, sortOrder: sortOrder);
  }

  /// [1. Create a folder] Prompts for a folder name, then creates it (G8: the
  /// VM owns the dialog). A cancelled/empty prompt is a no-op.
  Future<void> createFolderWithPrompt() async {
    final name = await arxaKitLocator<ArxaKitNotificationService>()
        .prompt(title: 'New Folder', placeholder: 'Name');
    if (name != null) await createFolder(name);
  }

  /// Prompts for a new name (pre-filled with the current one), then renames.
  Future<void> renameFolderWithPrompt(ShowcaseNoteFolderModel folder) async {
    final name = await arxaKitLocator<ArxaKitNotificationService>()
        .prompt(title: 'Rename Folder', initialValue: folder.name);
    if (name != null) await renameFolder(folder, name);
  }

  /// Asks first (hand-written — the message interpolates the folder name);
  /// on confirm the folder is deleted and its notes move to Recently Deleted.
  Future<void> confirmDeleteFolder(ShowcaseNoteFolderModel folder) async {
    final confirmed =
        await arxaKitLocator<ArxaKitNotificationService>().confirm(
      title: 'Delete Folder',
      message: 'Notes in "${folder.name}" will move to Recently Deleted.',
      actionLabel: 'Delete',
      destructive: true,
    );
    if (confirmed) await deleteFolder(folder);
  }

  Future<void> renameFolder(ShowcaseNoteFolderModel folder, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _service.renameFolder(folder, trimmed);
  }

  Future<void> deleteFolder(ShowcaseNoteFolderModel folder) =>
      _service.deleteFolder(folder);

  Future<void> signOut() => _service.signOut();

  // ── Cleanup ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _showCreateAccount.close();
    super.dispose();
  }
}
