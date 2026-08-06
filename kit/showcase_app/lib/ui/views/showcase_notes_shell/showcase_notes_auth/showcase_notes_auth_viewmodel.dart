import 'package:rxdart/rxdart.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:ui_library/ui_library.dart';

import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';

/// Which credential flow the auth screen shows. Owner-held, mirrors
/// [KitNativeSegmentedControl]'s index convention (see the view).
enum NotesAuthMode { password, otp }

/// Sign-in screen for the seed-backend smoke surface — streams-only (house
/// convention): `BaseViewModel` is a lifecycle token (creation/disposal via
/// StackedView), never a rebuild mechanism — `notifyListeners` is not called.
/// All live state is exposed as streams and the views bind them with
/// [KitStreamBuilder]:
///
/// - UI-owned state ([mode$], [otpRequested$], [errorMessage$]) is a seeded
///   [BehaviorSubject]; inline form errors stay inline (no snackbars).
/// - [busy$] is an rxdart composition over the per-op [KitAction.state$]
///   streams — the stream form of the old `.withLoading(setBusy)`, preserving
///   the "every button disabled while any auth op runs" behavior exactly.
///
/// Talks only to [ShowcaseNotesFacadeService.auth] — when a session appears,
/// the signed-out ShowcaseNotesView swaps this panel for the Folders list in
/// place (that binding lives on the parent VM; this one holds no session
/// state).
class ShowcaseNotesAuthViewModel extends KitViewModel {
  final ShowcaseNotesFacadeService _notes = locator<ShowcaseNotesFacadeService>();

  KitAuthService get auth => _notes.auth;

  /// Op labels of the auth ops — [busy$] composes their
  /// [KitAction.state$] streams; KitViewModel.dispose releases them.
  static const _ops = [
    'signIn',
    'signUp',
    'requestOtp',
    'confirmOtp',
    'google',
    'apple',
    'anonymous',
  ];

  /// Busy while ANY auth op is in flight. Seeded (no loading flash on first
  /// bind); one lazy composition per VM.
  late final ValueStream<bool> busy$ = Rx.combineLatest(
    [for (final op in _ops) actionState$(op).map((s) => s.busy)],
    (flags) => flags.any((busy) => busy),
  ).shareValueSeeded(false);

  /// The credential flow the segmented control selected.
  final BehaviorSubject<NotesAuthMode> _mode =
      BehaviorSubject<NotesAuthMode>.seeded(NotesAuthMode.password);
  ValueStream<NotesAuthMode> get mode$ => _mode.stream;

  /// Flips once [requestOtp] succeeds — the view then shows the code field.
  final BehaviorSubject<bool> _otpRequested = BehaviorSubject<bool>.seeded(false);
  ValueStream<bool> get otpRequested$ => _otpRequested.stream;

  /// Inline form error (seeded null = none). [KitAuthException] shows its
  /// message, anything unexpected gets the generic one — set from the
  /// KitAction chain's onError, never a snackbar.
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

  void setMode(NotesAuthMode value) {
    _mode.add(value);
    _otpRequested.add(false);
    code = '';
    _errorMessage.add(null);
  }

  /// Every auth call runs through KitAction: per-op busy state (bound via
  /// [busy$]), re-entry guard (double-tap dropped silently via the fallback),
  /// and errors surfaced inline as [errorMessage$].
  Future<void> _guard(Future<void> Function() action, String op) {
    _errorMessage.add(null);
    return KitAction.run<void>(operation: action, owner: this, op: op)
        .withErrorFallback('Authentication failed')
        .onError((e, _) {
          _errorMessage.add(
              e is KitAuthException ? e.message : 'Something went wrong. Try again.');
        })
        .execute();
  }

  Future<void> signInEmail(String email, String password) => _guard(
      () => auth.signInWithEmailPassword(email: email, password: password),
      'signIn');

  Future<void> signUpEmail(String email, String password) => _guard(
      () => auth.signUpWithEmailPassword(email: email, password: password),
      'signUp');

  Future<void> requestOtp(String email) => _guard(() async {
        await auth.requestOtp(email: email);
        _otpRequested.add(true);
      }, 'requestOtp');

  Future<void> confirmOtp(String email, String code) =>
      _guard(() => auth.confirmOtp(email: email, code: code),
          'confirmOtp');

  Future<void> google() =>
      _guard(() => auth.signInWithGoogle(), 'google');

  Future<void> apple() =>
      _guard(() => auth.signInWithApple(), 'apple');

  Future<void> anonymous() =>
      _guard(() => auth.signInAnonymously(), 'anonymous');

  @override
  void dispose() {
    _mode.close();
    _otpRequested.close();
    _errorMessage.close();
    super.dispose();
  }
}
