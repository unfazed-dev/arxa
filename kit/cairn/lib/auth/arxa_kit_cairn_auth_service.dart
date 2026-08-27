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
    required ArxaKitAuthService inner,
    required Future<void> Function() dbSignOut,
    // Private named parameters can't be initializing formals — ignore.
    // ignore: prefer_initializing_formals
  })  : _inner = inner,
        // ignore: prefer_initializing_formals
        _dbSignOut = dbSignOut;

  final ArxaKitAuthService _inner;
  final Future<void> Function() _dbSignOut;

  @override
  Stream<ArxaKitAuthSession?> get session$ => _inner.session$;

  @override
  ArxaKitAuthSession? get currentSession => _inner.currentSession;

  @override
  Future<ArxaKitAuthSession> signUpWithEmailPassword({
    required String email,
    required String password,
  }) =>
      _inner.signUpWithEmailPassword(email: email, password: password);

  @override
  Future<ArxaKitAuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) =>
      _inner.signInWithEmailPassword(email: email, password: password);

  @override
  Future<void> requestOtp({String? email, String? phone}) =>
      _inner.requestOtp(email: email, phone: phone);

  @override
  Future<ArxaKitAuthSession> confirmOtp({
    String? email,
    String? phone,
    required String code,
  }) =>
      _inner.confirmOtp(email: email, phone: phone, code: code);

  @override
  Future<ArxaKitAuthSession> signInWithGoogle() => _inner.signInWithGoogle();

  @override
  Future<ArxaKitAuthSession> signInWithApple() => _inner.signInWithApple();

  @override
  Future<ArxaKitAuthSession> signInAnonymously() => _inner.signInAnonymously();

  /// cairn first, Supabase second — see the library doc.
  @override
  Future<void> signOut() async {
    await _dbSignOut();
    await _inner.signOut();
  }

  @override
  Future<void> dispose() => _inner.dispose();
}
