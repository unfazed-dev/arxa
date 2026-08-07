/// The sign-in panel's viewmodel. The view calls actions in and reads streams
/// out: when the user does something, the matching action does the work; when
/// something changes, the new value flows down the stream and the view redraws
/// just the part listening to it. The viewmodel never touches the view — swap
/// the UI for any other and this file stays unchanged.
///
/// This is the business logic for the sign-in screen. A returning user signs in
/// with email and password or with a one-time code, or taps Google, Apple, or
/// the anonymous button to skip account creation entirely. While any sign-in is
/// in flight every button stays disabled; errors land inline under the form.
///
/// Requirements:
/// 1. [Email sign-in] — sign-in-with-email-and-otp
/// Two paths off one segmented control: password (sign in or sign up with
/// email + password) and OTP (request a code, then confirm it).
/// 2. [Google sign-in] — sign-in-with-google
/// The Google button signs the user in.
/// 3. [Apple sign-in] — sign-in-with-apple
/// The Apple button signs the user in.
/// 4. [Anonymous] — continue-anonymously
/// The anonymous button signs the user in without an account.
///
/// Relationships:
///
///      ┌──────────────────┐
///      │ notes auth view  │
///      └──────────────────┘
///      ACT ▼        ▲ STRM
///      [1-8]        [1-4]
///   ┌───────────────────────┐
///   │ notes auth viewmodel  │
///   └───────────────────────┘
///        ACT ▼    ▲ STRM
///        [1-7]
///        ┌──────────────┐
///        │ notes facade │
///        └──────────────┘
///  ════════ abxAction ════════
///
///  streams (STRM)        actions (ACT)          commands (CMD)
///    1. busy$             1. setMode             1. _signIn
///    2. mode$             2. signInEmail         2. _signUp
///    3. otpRequested$     3. signUpEmail         3. _requestOtp
///    4. errorMessage$     4. requestOtp          4. _confirmOtp
///                        5. confirmOtp           5. _google
///                        6. google               6. _apple
///                        7. apple                7. _anonymous
///                        8. anonymous
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_viewmodel.dart
library;

import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/enums/showcase_notes_enums/enums.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';

class ShowcaseNotesAuthViewModel extends AppBoxKitViewModel {
  // ── Setup ──────────────────────────────────────────────────────────────────

  final ShowcaseNotesFacadeService _notes = appBoxKitLocator<ShowcaseNotesFacadeService>();

  AppBoxKitAuthService get auth => _notes.auth;

  /// The auth ops — [busy$] composes their [AppBoxKitAction.state$] streams;
  /// AppBoxKitViewModel.dispose releases them.
  static final _ops = [for (final op in ShowcaseNotesAuthOp.values) op.name];

  /// Sends every auth op through the shared hub — busy state, double-tap
  /// guard, and inline errors come with it; the send returns after the op starts.
  @override
  AppBoxKitActionHub createHub() => AppBoxKitActionHub(
        owner: this,
        errorMessage: 'Authentication failed',
        onSend: () => _errorMessage.add(null),
        onError: (error) => _errorMessage.add(error is AppBoxKitAuthException
            ? error.message
            : 'Something went wrong. Try again.'),
      );

  // ── Initial state ─────────────────────────────────────────────────────────

  // Never-prefill credential capture (sign-in / OTP): plain string fields
  // written one-way from the view's onChanged, read at submit. No
  // TextEditingController in the viewmodel (1m) and no StatefulWidget form
  // host (state stays here, in the VM). Not streamed — nothing in the UI
  // reflects these until submit. See forms_playbook.mdx ("forms that never
  // prefill").
  /// [1. Email sign-in] Credentials captured one-way from the view, read at submit.
  String email = '';
  String password = '';
  String code = '';

  // ── Streams ─────────────────────────────────────────────────────────

  /// Busy while ANY auth op is in flight. Seeded (no loading flash on first
  /// bind); one lazy composition per VM.
  late final ValueStream<bool> busy$ = Rx.combineLatest(
    [for (final op in _ops) actionState$(op).map((state) => state.busy)],
    (flags) => flags.any((busy) => busy),
  ).shareValueSeeded(false);

  /// [1. Email sign-in] The credential flow the segmented control selected.
  final BehaviorSubject<ShowcaseNotesAuthMode> _mode =
      BehaviorSubject<ShowcaseNotesAuthMode>.seeded(ShowcaseNotesAuthMode.password);
  ValueStream<ShowcaseNotesAuthMode> get mode$ => _mode.stream;

  /// [1. Email sign-in] Flips once [requestOtp] succeeds — the view then shows the code field.
  final BehaviorSubject<bool> _otpRequested = BehaviorSubject<bool>.seeded(false);
  ValueStream<bool> get otpRequested$ => _otpRequested.stream;

  /// Inline form error (seeded null = none): auth errors show their message,
  /// anything else gets the generic one.
  final BehaviorSubject<String?> _errorMessage =
      BehaviorSubject<String?>.seeded(null);
  ValueStream<String?> get errorMessage$ => _errorMessage.stream;

  // ── Commands ─────────────────────────────────────────
  // Commands decide when — and whether — Actions run.

  /// [1. Email sign-in] Password path — sign in with email + password.
  late final _signIn = abxActionHub.on<(String, String), void>(ShowcaseNotesAuthOp.signIn.name,
      (p) => auth.signInWithEmailPassword(email: p.$1, password: p.$2));

  /// [1. Email sign-in] Password path — sign up with email + password.
  late final _signUp = abxActionHub.on<(String, String), void>(ShowcaseNotesAuthOp.signUp.name,
      (p) => auth.signUpWithEmailPassword(email: p.$1, password: p.$2));

  /// [1. Email sign-in] OTP path — request a one-time code for the email.
  late final _requestOtp =
      abxActionHub.on<String, void>(ShowcaseNotesAuthOp.requestOtp.name, (email) async {
    await auth.requestOtp(email: email);
    _otpRequested.add(true);
  });

  /// [1. Email sign-in] OTP path — confirm the code the user entered.
  late final _confirmOtp = abxActionHub.on<(String, String), void>(
      ShowcaseNotesAuthOp.confirmOtp.name, (p) => auth.confirmOtp(email: p.$1, code: p.$2));

  /// [2. Google sign-in] Signs the user in with Google.
  late final _google =
      abxActionHub.on<Null, void>(ShowcaseNotesAuthOp.google.name, (_) => auth.signInWithGoogle());

  /// [3. Apple sign-in] Signs the user in with Apple.
  late final _apple =
      abxActionHub.on<Null, void>(ShowcaseNotesAuthOp.apple.name, (_) => auth.signInWithApple());

  /// [4. Anonymous] Signs the user in without an account.
  late final _anonymous =
      abxActionHub.on<Null, void>(ShowcaseNotesAuthOp.anonymous.name, (_) => auth.signInAnonymously());

  // ── Actions ──────────────────────────────────────────

  /// [1. Email sign-in] Switches the segmented control and resets OTP / error state.
  void setMode(ShowcaseNotesAuthMode value) {
    _mode.add(value);
    _otpRequested.add(false);
    code = '';
    _errorMessage.add(null);
  }

  /// [1. Email sign-in] Password path — sign in.
  Future<void> signInEmail(String email, String password) =>
      _signIn.send((email, password));

  /// [1. Email sign-in] Password path — sign up.
  Future<void> signUpEmail(String email, String password) =>
      _signUp.send((email, password));

  /// [1. Email sign-in] OTP path — request a code.
  Future<void> requestOtp(String email) => _requestOtp.send(email);

  /// [1. Email sign-in] OTP path — confirm the code.
  Future<void> confirmOtp(String email, String code) =>
      _confirmOtp.send((email, code));

  /// [2. Google sign-in] Starts the Google sign-in flow.
  Future<void> google() => _google.send(null);

  /// [3. Apple sign-in] Starts the Apple sign-in flow.
  Future<void> apple() => _apple.send(null);

  /// [4. Anonymous] Signs in without an account.
  Future<void> anonymous() => _anonymous.send(null);

  // ── Cleanup ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _mode.close();
    _otpRequested.close();
    _errorMessage.close();
    // The hub dies in super.dispose() → disposeAppBoxKitActions.
    super.dispose();
  }
}
