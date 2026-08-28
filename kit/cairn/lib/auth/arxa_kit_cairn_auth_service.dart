/// Auth decorator for the supabaseBridge mode: every call delegates to the
/// wrapped service EXCEPT [signOut], which signs the cairn database out FIRST
/// (wipe local rows + outbox, deregister push tokens) and only then ends the
/// Supabase session. The ordering is load-bearing: cairn's sign-out hooks
/// authorize their REST calls with the live session, which 401s once Supabase
/// has already signed out (ADR-0037 §3 / L1).
library;

import 'package:arxa_kit_data/arxa_kit_data.dart';

class ArxaKitCairnAuthService implements ArxaKitAuthService {
  ArxaKitCairnAuthService({
    required this.inner,
    required this.dbSignOut,
  });

  /// The wrapped service (kit/data's Supabase auth in the wired backend).
  final ArxaKitAuthService inner;

  /// `CairnDatabase.signOut` — runs BEFORE [inner]'s signOut.
  final Future<void> Function() dbSignOut;

  @override
  Stream<ArxaKitAuthSession?> get session$ => inner.session$;

  @override
  ArxaKitAuthSession? get currentSession => inner.currentSession;

  @override
  Future<ArxaKitAuthSession> signUpWithEmailPassword({
    required String email,
    required String password,
  }) =>
      inner.signUpWithEmailPassword(email: email, password: password);

  @override
  Future<ArxaKitAuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) =>
      inner.signInWithEmailPassword(email: email, password: password);

  @override
  Future<void> requestOtp({String? email, String? phone}) =>
      inner.requestOtp(email: email, phone: phone);

  @override
  Future<ArxaKitAuthSession> confirmOtp({
    String? email,
    String? phone,
    required String code,
  }) =>
      inner.confirmOtp(email: email, phone: phone, code: code);

  @override
  Future<ArxaKitAuthSession> signInWithGoogle() => inner.signInWithGoogle();

  @override
  Future<ArxaKitAuthSession> signInWithApple() => inner.signInWithApple();

  @override
  Future<ArxaKitAuthSession> signInAnonymously() => inner.signInAnonymously();

  /// cairn first, Supabase second — see the library doc.
  @override
  Future<void> signOut() async {
    await dbSignOut();
    await inner.signOut();
  }

  @override
  Future<void> dispose() => inner.dispose();
}
