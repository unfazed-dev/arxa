/// The create-account panel's viewmodel. The view calls actions in and reads
/// streams out: when the user does something, the matching action does the
/// work; when something changes, the new value flows down the stream and the
/// view redraws just the part listening to it. The viewmodel never touches the
/// view — swap the UI for any other and this file stays unchanged.
///
/// This is the business logic for the create-account screen. A new user enters
/// an email and password and taps create — the form stays disabled while the
/// request runs, and any error lands inline under the field that caused it.
///
/// Requirements:
/// 1. [Create account] — create-account-with-email-and-otp
/// An email and password create a new account.
///
/// Relationships:
///
///       ┌────────────────────────────┐
///       │ notes create account view  │
///       └────────────────────────────┘
///       ACT ▼                  ▲ STRM
///       [1-2]
///   ┌───────────────────────────────────┐
///   │  notes create account viewmodel   │
///   └───────────────────────────────────┘
///             ACT ▼
///             [1]
///             ┌──────────────┐
///             │ notes facade │
///             └──────────────┘
///        ════════ abxAction ════════
///
///  streams (STRM)          actions (ACT)          commands (CMD)
///    1. signUpState$        1. createAccount       1. _signUp
///    2. errorMessage$
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_notes_create_account/showcase_notes_create_account_viewmodel.dart
library;

import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/enums/showcase_notes_enums/enums.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';

class ShowcaseNotesCreateAccountViewModel extends AppBoxKitViewModel {
  // ── Setup ──────────────────────────────────────────────────────────────────

  final ShowcaseNotesFacadeService _notes =
      appBoxKitLocator<ShowcaseNotesFacadeService>();

  AppBoxKitAuthService get auth => _notes.auth;

  // ── Initial state ─────────────────────────────────────────────────────────

  // Never-prefill credential capture: plain string fields written one-way from
  // the view's onChanged, read at submit. No TextEditingController in the
  // viewmodel (1m) and no StatefulWidget form host. Not streamed — nothing
  // reflects these until submit. See forms_playbook.mdx.
  /// [1. Create account] Credentials captured one-way from the view, read at submit.
  String email = '';
  String password = '';

  // ── Streams ─────────────────────────────────────────────────────────

  /// [1. Create account] Live busy/error state of the sign-up op — the stream
  /// form of the old `.withLoading(setBusy)`: the form binds it to disable
  /// buttons and show the inline spinner while sign-up runs.
  ValueStream<AppBoxKitActionState> get signUpState$ =>
      actionState$(ShowcaseNotesAuthOp.signUp.name);

  /// Inline form error (seeded null = none): auth errors show their message,
  /// anything else gets the generic one.
  final BehaviorSubject<String?> _errorMessage =
      BehaviorSubject<String?>.seeded(null);
  ValueStream<String?> get errorMessage$ => _errorMessage.stream;

  // ── Commands ─────────────────────────────────────────
  // Commands decide when — and whether — Actions run.

  /// [1. Create account] Hot-send sign-up: per-op busy state, double-tap
  /// guard, and inline errors via [errorMessage$].
  late final _signUp = abxActionHub.on<(String, String), void>(
    ShowcaseNotesAuthOp.signUp.name,
    (p) => auth.signUpWithEmailPassword(email: p.$1, password: p.$2),
    errorMessage: 'Sign-up failed',
    onSend: () => _errorMessage.add(null),
    onError: (error) => _errorMessage.add(error is AppBoxKitAuthException
        ? error.message
        : 'Something went wrong. Try again.'),
  );

  // ── Actions ──────────────────────────────────────────

  /// [1. Create account] Creates the account with the entered email and password.
  Future<void> createAccount(String email, String password) =>
      _signUp.send((email, password));

  // ── Cleanup ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _errorMessage.close();
    super.dispose();
  }
}
