import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/enums/showcase_notes_enums/enums.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';

/// Sign-in screen for the seed-backend smoke surface — streams-only (house
/// convention): `BaseViewModel` is a lifecycle token (creation/disposal via
/// StackedView), never a rebuild mechanism — `notifyListeners` is not called.
/// All live state is exposed as streams and the views bind them with
/// [AppBoxKitStreamBuilder]:
///
/// - UI-owned state ([mode$], [otpRequested$], [errorMessage$]) is a seeded
///   [BehaviorSubject]; inline form errors stay inline (no snackbars).
/// - [busy$] is an rxdart composition over the per-op [AppBoxKitAction.state$]
///   streams — the stream form of the old `.withLoading(setBusy)`, preserving
///   the "every button disabled while any auth op runs" behavior exactly.
///
/// Talks only to [ShowcaseNotesFacadeService.auth] — when a session appears,
/// the signed-out ShowcaseNotesView swaps this panel for the Folders list in
/// place (that binding lives on the parent VM; this one holds no session
/// state).
class ShowcaseNotesAuthViewModel extends AppBoxKitViewModel {
  final ShowcaseNotesFacadeService _notes = appBoxKitLocator<ShowcaseNotesFacadeService>();

  AppBoxKitAuthService get auth => _notes.auth;

  /// The auth ops — [busy$] composes their [AppBoxKitAction.state$] streams;
  /// AppBoxKitViewModel.dispose releases them.
  static final _ops = [for (final op in ShowcaseNotesAuthOp.values) op.name];

  /// Busy while ANY auth op is in flight. Seeded (no loading flash on first
  /// bind); one lazy composition per VM.
  late final ValueStream<bool> busy$ = Rx.combineLatest(
    [for (final op in _ops) actionState$(op).map((state) => state.busy)],
    (flags) => flags.any((busy) => busy),
  ).shareValueSeeded(false);

  /// The credential flow the segmented control selected.
  final BehaviorSubject<ShowcaseNotesAuthMode> _mode =
      BehaviorSubject<ShowcaseNotesAuthMode>.seeded(ShowcaseNotesAuthMode.password);
  ValueStream<ShowcaseNotesAuthMode> get mode$ => _mode.stream;

  /// Flips once [requestOtp] succeeds — the view then shows the code field.
  final BehaviorSubject<bool> _otpRequested = BehaviorSubject<bool>.seeded(false);
  ValueStream<bool> get otpRequested$ => _otpRequested.stream;

  /// Inline form error (seeded null = none). [AppBoxKitAuthException] shows its
  /// message, anything unexpected gets the generic one — set from the
  /// hub's onError tap, never a snackbar.
  final BehaviorSubject<String?> _errorMessage =
      BehaviorSubject<String?>.seeded(null);
  ValueStream<String?> get errorMessage$ => _errorMessage.stream;

  // Never-prefill credential capture (sign-in / OTP): plain string fields
  // written one-way from the view's onChanged, read at submit. No
  // TextEditingController in the viewmodel (1m) and no StatefulWidget form
  // host (state stays here, in the VM). Not streamed — nothing in the UI
  // reflects these until submit. See forms_playbook.mdx ("forms that never
  // prefill").
  String email = '';
  String password = '';
  String code = '';

  void setMode(ShowcaseNotesAuthMode value) {
    _mode.add(value);
    _otpRequested.add(false);
    code = '';
    _errorMessage.add(null);
  }

  /// Every auth op is a hot-send command on the AppBoxKitActionOwner
  /// hub: per-op busy state via the same actionState$ machinery (bound
  /// via [busy$]), re-entry guard (a double-tap's handle observes the
  /// in-flight run instead of re-running), errors surfaced inline as
  /// [errorMessage$]. The methods below return the send's observation
  /// handle — the op is already running when they return, so the views'
  /// fire-and-forget callbacks can never drop it.
  @override
  AppBoxKitActionHub createHub() => AppBoxKitActionHub(
        owner: this,
        errorMessage: 'Authentication failed',
        onSend: () => _errorMessage.add(null),
        onError: (error) => _errorMessage.add(error is AppBoxKitAuthException
            ? error.message
            : 'Something went wrong. Try again.'),
      );

  late final _signIn = abxActionHub.on<(String, String), void>(ShowcaseNotesAuthOp.signIn.name,
      (p) => auth.signInWithEmailPassword(email: p.$1, password: p.$2));

  late final _signUp = abxActionHub.on<(String, String), void>(ShowcaseNotesAuthOp.signUp.name,
      (p) => auth.signUpWithEmailPassword(email: p.$1, password: p.$2));

  late final _requestOtp =
      abxActionHub.on<String, void>(ShowcaseNotesAuthOp.requestOtp.name, (email) async {
    await auth.requestOtp(email: email);
    _otpRequested.add(true);
  });

  late final _confirmOtp = abxActionHub.on<(String, String), void>(
      ShowcaseNotesAuthOp.confirmOtp.name, (p) => auth.confirmOtp(email: p.$1, code: p.$2));

  late final _google =
      abxActionHub.on<Null, void>(ShowcaseNotesAuthOp.google.name, (_) => auth.signInWithGoogle());

  late final _apple =
      abxActionHub.on<Null, void>(ShowcaseNotesAuthOp.apple.name, (_) => auth.signInWithApple());

  late final _anonymous =
      abxActionHub.on<Null, void>(ShowcaseNotesAuthOp.anonymous.name, (_) => auth.signInAnonymously());

  Future<void> signInEmail(String email, String password) =>
      _signIn.send((email, password));

  Future<void> signUpEmail(String email, String password) =>
      _signUp.send((email, password));

  Future<void> requestOtp(String email) => _requestOtp.send(email);

  Future<void> confirmOtp(String email, String code) =>
      _confirmOtp.send((email, code));

  Future<void> google() => _google.send(null);

  Future<void> apple() => _apple.send(null);

  Future<void> anonymous() => _anonymous.send(null);

  @override
  void dispose() {
    _mode.close();
    _otpRequested.close();
    _errorMessage.close();
    // The hub dies in super.dispose() → disposeAppBoxKitActions.
    super.dispose();
  }
}
