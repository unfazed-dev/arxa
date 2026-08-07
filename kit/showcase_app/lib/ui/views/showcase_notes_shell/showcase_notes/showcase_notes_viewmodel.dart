import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';

/// The "Folders" screen viewmodel — streams-only (house convention): all
/// state is exposed as streams and the views bind them with [AppBoxKitStreamBuilder];
/// `BaseViewModel` is a lifecycle token (creation/disposal via StackedView),
/// never a rebuild mechanism — `notifyListeners` is not called.
///
/// Data streams are facade pass-throughs composed with rxdart `switchMap`
/// (session → owner-scoped reads), so the VM holds no relay fields and no
/// subscription bookkeeping for them — each [AppBoxKitStreamBuilder] owns its
/// subscription. The one VM-owned UI state, [showCreateAccount$], is a
/// seeded [BehaviorSubject]; the only [AppBoxKitAction.listen] left is the
/// VM-internal side effect that resets it when a session appears.
class ShowcaseNotesViewModel extends AppBoxKitViewModel {
  final _service = appBoxKitLocator<ShowcaseNotesFacadeService>();

  /// Null while signed out — the views swap to the auth surface on null.
  Stream<AppBoxKitAuthSession?> get session$ => _service.session$;

  /// Owner-scoped folder overview; null while signed out.
  Stream<ShowcaseNotesOverview?> get overview$ => _service.session$.switchMap(
        (session) => session == null
            ? Stream<ShowcaseNotesOverview?>.value(null)
            : _service.overview$(session.user.id),
      );

  /// Cross-owner folders + counts; emits non-null only while an admin session
  /// is live, so the views gate the "All users (admin)" section on presence.
  ///
  /// DEMO ONLY — not a security boundary. The admin role comes from seeded
  /// identity metadata on a fake local backend; real apps must enforce
  /// authorization server-side, never via client-side gating like this.
  Stream<ShowcaseNotesAdminOverview?> get adminOverview$ =>
      _service.session$.switchMap(
        (session) => ShowcaseNotesFacadeService.isAdminSession(session)
            ? _service.adminOverview$()
            : Stream<ShowcaseNotesAdminOverview?>.value(null),
      );

  /// When signed out, the Notes tab shows the create-account panel instead of
  /// the sign-in panel. Owner-held here (not in the transient views) and reset
  /// whenever a session appears, so signing in — from either panel — always
  /// swaps back cleanly.
  final BehaviorSubject<bool> _showCreateAccount =
      BehaviorSubject<bool>.seeded(false);
  ValueStream<bool> get showCreateAccount$ => _showCreateAccount.stream;

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

  void openCreateAccount() => _showCreateAccount.add(true);

  void closeCreateAccount() => _showCreateAccount.add(false);

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

  /// Prompts for a folder name, then creates it (G8: the VM owns the dialog).
  /// A cancelled/empty prompt is a no-op.
  Future<void> createFolderWithPrompt() async {
    final name = await appBoxKitLocator<AppBoxKitNotificationService>()
        .prompt(title: 'New Folder', placeholder: 'Name');
    if (name != null) await createFolder(name);
  }

  /// Prompts for a new name (pre-filled with the current one), then renames.
  Future<void> renameFolderWithPrompt(ShowcaseNoteFolderModel folder) async {
    final name = await appBoxKitLocator<AppBoxKitNotificationService>()
        .prompt(title: 'Rename Folder', initialValue: folder.name);
    if (name != null) await renameFolder(folder, name);
  }

  /// Asks first — hand-written because the message interpolates the folder
  /// name (the hub's confirm gate takes static strings; see `hub.on`).
  /// On confirm the folder is deleted (its live notes move to Recently
  /// Deleted — the facade owns that semantic).
  Future<void> confirmDeleteFolder(ShowcaseNoteFolderModel folder) async {
    final confirmed = await appBoxKitLocator<AppBoxKitNotificationService>()
        .confirm(
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

  @override
  void dispose() {
    _showCreateAccount.close();
    super.dispose();
  }
}
