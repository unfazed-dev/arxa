import 'package:rxdart/rxdart.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:ui_library/ui_library.dart';

import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';

/// Create-account panel for the seed-backend smoke surface — streams-only
/// (house convention): `BaseViewModel` is a lifecycle token (creation/disposal
/// via StackedView), never a rebuild mechanism — `notifyListeners` is not
/// called. The views bind [errorMessage$] (VM-owned seeded [BehaviorSubject];
/// inline form errors stay inline, no snackbars) and [signUpState$] (the
/// KitAction op's busy/error stream) with [KitStreamBuilder].
///
/// Talks only to [ShowcaseNotesFacadeService.auth] — when sign-up succeeds a
/// session appears on the stream and the signed-out ShowcaseNotesView swaps
/// this panel away in place; the view itself never navigates.
class ShowcaseNotesCreateAccountViewModel extends KitViewModel {
  final ShowcaseNotesFacadeService _notes = locator<ShowcaseNotesFacadeService>();

  KitAuthService get auth => _notes.auth;

  /// Live busy/error state of the sign-up op — the stream form of the old
  /// `.withLoading(setBusy)`: the form binds it to disable buttons and show
  /// the inline spinner while sign-up runs.
  ValueStream<KitActionState> get signUpState$ => actionState$('signUp');

  // Never-prefill credential capture: plain string fields written one-way from
  // the view's onChanged, read at submit. No TextEditingController in the
  // viewmodel (1m) and no StatefulWidget form host. Not streamed — nothing
  // reflects these until submit. See forms_playbook.mdx.
  String email = '';
  String password = '';

  /// Inline form error (seeded null = none). [KitAuthException] shows its
  /// message, anything unexpected gets the generic one — set from the
  /// KitAction chain's onError, never a snackbar.
  final BehaviorSubject<String?> _errorMessage =
      BehaviorSubject<String?>.seeded(null);
  ValueStream<String?> get errorMessage$ => _errorMessage.stream;

  /// Same KitAction guard as the auth viewmodel: per-op busy state (bound via
  /// [signUpState$]), re-entry guard, [KitAuthException] surfaced inline as
  /// [errorMessage$].
  Future<void> createAccount(String email, String password) {
    _errorMessage.add(null);
    return KitAction.run<void>(
      operation: () =>
          auth.signUpWithEmailPassword(email: email, password: password),
      owner: this,
      op: 'signUp',
    )
        .withErrorFallback('Sign-up failed')
        .onError((e, _) {
          _errorMessage.add(
              e is KitAuthException ? e.message : 'Something went wrong. Try again.');
        })
        .execute();
  }

  @override
  void dispose() {
    _errorMessage.close();
    super.dispose();
  }
}
