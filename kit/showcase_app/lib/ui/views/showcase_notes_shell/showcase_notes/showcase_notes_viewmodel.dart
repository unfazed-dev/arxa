import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:appbox_kit_core/kit_locator.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';

import 'package:appbox_kit_showcase_app/models/showcase_note_folder.dart';
import 'package:appbox_kit_showcase_app/services/facades/showcase_notes_facade.dart';

/// The "Folders" screen viewmodel. Subscribes to [ShowcaseNotesFacade.session$] and,
/// once signed in, to [ShowcaseNotesFacade.overview$] — both fields are plain and
/// pushed via `notifyListeners`, no double-buffering through a second stream
/// layer.
class ShowcaseNotesViewModel extends BaseViewModel {
  final _service = locator<ShowcaseNotesFacade>();

  StreamSubscription<KitAuthSession?>? _sessionSub;
  StreamSubscription<ShowcaseNotesOverview>? _overviewSub;
  StreamSubscription<ShowcaseNotesAdminOverview>? _adminSub;

  KitAuthSession? session;
  ShowcaseNotesOverview? overview;

  /// Cross-owner folders + counts; non-null only while an admin session is
  /// live, so the views can gate the "All users (admin)" section on presence.
  ///
  /// DEMO ONLY — not a security boundary. The admin role comes from seeded
  /// identity metadata on a fake local backend; real apps must enforce
  /// authorization server-side, never via client-side gating like this.
  ShowcaseNotesAdminOverview? adminOverview;

  /// When signed out, the Notes tab shows the create-account panel instead of
  /// the sign-in panel. Owner-held here (not in the transient views) and reset
  /// whenever a session appears, so signing in — from either panel — always
  /// swaps back cleanly.
  bool showCreateAccount = false;

  ShowcaseNotesViewModel() {
    _sessionSub = _service.session$.listen((session) {
      this.session = session;
      _overviewSub?.cancel();
      _overviewSub = null;
      overview = null;
      _adminSub?.cancel();
      _adminSub = null;
      adminOverview = null;
      if (session != null) {
        showCreateAccount = false;
        _overviewSub = _service.overview$(session.user.id).listen((overview) {
          this.overview = overview;
          notifyListeners();
        });
        if (ShowcaseNotesFacade.isAdminSession(session)) {
          _adminSub = _service.adminOverview$().listen((admin) {
            adminOverview = admin;
            notifyListeners();
          });
        }
      }
      notifyListeners();
    });
  }

  void openCreateAccount() {
    showCreateAccount = true;
    notifyListeners();
  }

  void closeCreateAccount() {
    showCreateAccount = false;
    notifyListeners();
  }

  Future<void> createFolder(String name) async {
    final owner = session?.user.id;
    final trimmed = name.trim();
    if (owner == null || trimmed.isEmpty) return;
    await _service.createFolder(
      owner,
      trimmed,
      sortOrder: overview?.folders.length ?? 0,
    );
  }

  Future<void> renameFolder(ShowcaseNoteFolder folder, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _service.renameFolder(folder, trimmed);
  }

  Future<void> deleteFolder(ShowcaseNoteFolder folder) => _service.deleteFolder(folder);

  Future<void> signOut() => _service.signOut();

  @override
  void dispose() {
    _sessionSub?.cancel();
    _overviewSub?.cancel();
    _adminSub?.cancel();
    super.dispose();
  }
}
