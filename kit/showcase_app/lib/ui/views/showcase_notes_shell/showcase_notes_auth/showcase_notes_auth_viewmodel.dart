import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:appbox_kit_core/kit_locator.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';

import 'package:appbox_kit_showcase_app/services/facades/showcase_notes_facade.dart';

/// Which credential flow the auth screen shows. Owner-held, mirrors
/// [KitNativeSegmentedControl]'s index convention (see the view).
enum NotesAuthMode { password, otp }

/// Sign-in screen for the seed-backend smoke surface. Talks only to
/// [ShowcaseNotesFacade.auth] — when a session appears, the signed-out ShowcaseNotesView
/// swaps the embedded panel for the Folders list in place.
class ShowcaseNotesAuthViewModel extends BaseViewModel {
  final ShowcaseNotesFacade _notes = locator<ShowcaseNotesFacade>();

  KitAuthService get auth => _notes.auth;

  late final StreamSubscription<KitAuthSession?> _sessionSub;

  KitAuthSession? session;
  NotesAuthMode mode = NotesAuthMode.password;

  /// Flips once [requestOtp] succeeds — the view then shows the code field.
  bool otpRequested = false;

  // Never-prefill credential capture (sign-in / OTP): plain string fields
  // written one-way from the view's onChanged, read at submit. No
  // TextEditingController in the viewmodel (1m) and no StatefulWidget form
  // host (state stays here, in the VM). No notifyListeners — nothing in the
  // UI reflects these until submit, so rebuilds would be wasted. See
  // forms_playbook.mdx ("forms that never prefill").
  String email = '';
  String password = '';
  String code = '';

  String? errorMessage;

  ShowcaseNotesAuthViewModel() {
    session = auth.currentSession;
    _sessionSub = auth.session$.listen((s) {
      session = s;
      notifyListeners();
    });
  }

  void setMode(NotesAuthMode value) {
    mode = value;
    otpRequested = false;
    code = '';
    errorMessage = null;
    notifyListeners();
  }

  Future<void> _guard(Future<void> Function() action) async {
    errorMessage = null;
    setBusy(true);
    try {
      await action();
    } on KitAuthException catch (e) {
      errorMessage = e.message;
    } finally {
      setBusy(false);
    }
  }

  Future<void> signInEmail(String email, String password) => _guard(
      () => auth.signInWithEmailPassword(email: email, password: password));

  Future<void> signUpEmail(String email, String password) => _guard(
      () => auth.signUpWithEmailPassword(email: email, password: password));

  Future<void> requestOtp(String email) => _guard(() async {
        await auth.requestOtp(email: email);
        otpRequested = true;
      });

  Future<void> confirmOtp(String email, String code) =>
      _guard(() => auth.confirmOtp(email: email, code: code));

  Future<void> google() => _guard(() => auth.signInWithGoogle());

  Future<void> apple() => _guard(() => auth.signInWithApple());

  Future<void> anonymous() => _guard(() => auth.signInAnonymously());

  @override
  void dispose() {
    _sessionSub.cancel();
    super.dispose();
  }
}
