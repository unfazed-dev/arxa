import 'package:stacked/stacked.dart';
import 'package:appbox_kit_core/kit_locator.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';

import 'package:appbox_kit_showcase_app/services/facades/notes_facade.dart';

/// Create-account panel for the seed-backend smoke surface. Talks only to
/// [NotesFacade.auth] — when sign-up succeeds a session appears on the
/// stream and the signed-out ShowcaseNotesView swaps this panel away in
/// place; the view itself never navigates.
class ShowcaseNotesCreateAccountViewModel extends BaseViewModel {
  final NotesFacade _notes = locator<NotesFacade>();

  KitAuthService get auth => _notes.auth;

  // Never-prefill credential capture: plain string fields written one-way from
  // the view's onChanged, read at submit. No TextEditingController in the
  // viewmodel (1m) and no StatefulWidget form host. No notifyListeners —
  // nothing reflects these until submit. See forms_playbook.mdx.
  String email = '';
  String password = '';

  String? errorMessage;

  /// Mirrors the auth viewmodel's `_guard`: surface [KitAuthException] as
  /// [errorMessage], everything else propagates.
  Future<void> createAccount(String email, String password) async {
    errorMessage = null;
    setBusy(true);
    try {
      await auth.signUpWithEmailPassword(email: email, password: password);
    } on KitAuthException catch (e) {
      errorMessage = e.message;
    } finally {
      setBusy(false);
    }
  }
}
