import 'package:rxdart/rxdart.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:ui_library/ui_library.dart';

import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_folder_model.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';

// The view knows its viewmodel ONLY — every type a view needs to name (the
// stream payloads) is re-exported here so view files never import services,
// repositories, or data/model packages directly.
export 'package:appbox_kit_data/appbox_kit_data.dart' show KitAuthSession;
export 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_folder_model.dart';
export 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart'
    show ShowcaseNotesAdminOverview, ShowcaseNotesOverview;

/// The "Folders" screen viewmodel — streams-only (house convention): all
/// state is exposed as streams and the views bind them with [KitStreamBuilder];
/// `BaseViewModel` is a lifecycle token (creation/disposal via StackedView),
/// never a rebuild mechanism — `notifyListeners` is not called.
///
/// Data streams are facade pass-throughs composed with rxdart `switchMap`
/// (session → owner-scoped reads), so the VM holds no relay fields and no
/// subscription bookkeeping for them — each [KitStreamBuilder] owns its
/// subscription. The one VM-owned UI state, [showCreateAccount$], is a
/// seeded [BehaviorSubject]; the only [KitAction.watch] left is the
/// VM-internal side effect that resets it when a session appears.
class ShowcaseNotesViewModel extends KitViewModel {
  final _service = locator<ShowcaseNotesFacadeService>();

  /// Null while signed out — the views swap to the auth surface on null.
  Stream<KitAuthSession?> get session$ => _service.session$;

  /// Owner-scoped folder overview; null while signed out.
  Stream<ShowcaseNotesOverview?> get overview$ => _service.session$.switchMap(
        (s) => s == null
            ? Stream<ShowcaseNotesOverview?>.value(null)
            : _service.overview$(s.user.id),
      );

  /// Cross-owner folders + counts; emits non-null only while an admin session
  /// is live, so the views gate the "All users (admin)" section on presence.
  ///
  /// DEMO ONLY — not a security boundary. The admin role comes from seeded
  /// identity metadata on a fake local backend; real apps must enforce
  /// authorization server-side, never via client-side gating like this.
  Stream<ShowcaseNotesAdminOverview?> get adminOverview$ =>
      _service.session$.switchMap(
        (s) => ShowcaseNotesFacadeService.isAdminSession(s)
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
    // session appears. One watch, one dispose — the data streams above need
    // no subscription management here.
    KitAction.watch(
      owner: this,
      streams: [_service.session$],
      callback: (s) {
        if (s != null) _showCreateAccount.add(false);
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
        .then((o) => o.folders.length);
    await _service.createFolder(owner, trimmed, sortOrder: sortOrder);
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
