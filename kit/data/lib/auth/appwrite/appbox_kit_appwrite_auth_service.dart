/// [AppBoxKitAuthService] backed by Appwrite's `Account` API.
library;

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;
import 'package:appwrite/models.dart' as models;
import 'package:rxdart/rxdart.dart';

import '../../ids/appbox_kit_id_service.dart';
import '../appbox_kit_auth_service.dart';
import '../appbox_kit_auth_types.dart';

/// Appwrite implementation of [AppBoxKitAuthService], built on `Account`
/// (`appwrite-25.2.0/lib/services/account.dart` — every call below cites the
/// line it was verified against).
///
/// Constraints:
/// - Appwrite's Flutter SDK exposes no auth-state stream — it's a stateless
///   REST(+cookie) client; the documented way to know "am I signed in" is
///   `Account.get()` (`account.dart:9`), which throws a 401
///   [AppwriteException] when signed out. This service therefore owns a
///   [BehaviorSubject] fed by [initialize] and by every method that changes
///   the session — this is NOT a double-buffer of an existing reactive
///   source (there is none to double-buffer here), it's the *only* reactive
///   source, same justification as the seed backend's subject.
/// - Every method that establishes a session ends by calling
///   `_refreshSession`, which re-fetches `Account.get()` rather than trying
///   to build a [AppBoxKitAuthUser] out of whatever partial shape each
///   session-creating call happens to return — one mapping path for every
///   sign-in method, matching this package's "one code path" convention.
class AppBoxKitAppwriteAuthService implements AppBoxKitAuthService {
  AppBoxKitAppwriteAuthService({
    required Account account,
    required AppBoxKitIdService idService,
  })  : _account = account,
        _idService = idService;

  final Account _account;
  final AppBoxKitIdService _idService;

  final BehaviorSubject<AppBoxKitAuthSession?> _session$ =
      BehaviorSubject<AppBoxKitAuthSession?>();

  /// The userId a pending [requestOtp] targeted, so [confirmOtp] can resolve
  /// it even when a caller omits email/phone on the confirm call (mirrors
  /// `AppBoxKitSeedAuthService`'s `_pendingOtpEmail`/`_pendingOtpPhone` pattern).
  String? _pendingOtpUserId;

  /// Seeds [session$] from `Account.get()`
  /// (`account.dart:9` — "Get the currently logged in user."). A 401
  /// [AppwriteException] means signed out, per Appwrite's documented
  /// behavior for this endpoint; any other error is a real failure and is
  /// rethrown rather than silently treated as signed-out.
  Future<void> initialize() async {
    try {
      final user = await _account.get();
      _session$.add(_sessionFromUser(user));
    } on AppwriteException catch (error) {
      if (error.code == 401) {
        _session$.add(null);
      } else {
        rethrow;
      }
    }
  }

  @override
  Stream<AppBoxKitAuthSession?> get session$ => _session$.stream;

  @override
  AppBoxKitAuthSession? get currentSession => _session$.valueOrNull;

  @override
  Future<AppBoxKitAuthSession> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final userId = _idService.canonicalId(kAppBoxKitAuthUsersTable, email.toLowerCase());
    try {
      // `Account.create` (`account.dart:32`) registers a user but returns a
      // `models.User`, never a `models.Session` — it does NOT log the user
      // in. A session must be created explicitly afterward, same as the
      // Appwrite web/server SDKs' own two-step signup+session pattern.
      await _account.create(userId: userId, email: email, password: password);
      await _account.createEmailPasswordSession(email: email, password: password);
      return await _refreshSession();
    } on AppwriteException catch (error) {
      throw _wrap('Sign-up failed', error);
    }
  }

  @override
  Future<AppBoxKitAuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      // `createEmailPasswordSession` (`account.dart:835`) is the direct
      // login endpoint — no separate `create` call needed for an existing
      // user.
      await _account.createEmailPasswordSession(email: email, password: password);
      return await _refreshSession();
    } on AppwriteException catch (error) {
      throw _wrap('Sign-in failed', error);
    }
  }

  @override
  Future<void> requestOtp({String? email, String? phone}) async {
    if ((email == null) == (phone == null)) {
      // Not an `assert` — asserts strip in release builds and this
      // constraint must hold in production too.
      throw const AppBoxKitAuthException(
        'requestOtp requires exactly one of email or phone',
        code: 'invalid-otp-target',
      );
    }
    final identity = (email ?? phone!).toLowerCase();
    final userId = _idService.canonicalId(kAppBoxKitAuthUsersTable, identity);
    try {
      if (email != null) {
        // `createEmailToken` (`account.dart:1158`) requires both `userId`
        // and `email`; if `userId` hasn't been registered yet, Appwrite
        // auto-creates it — matching the fake backend's "unknown identities
        // are auto-created on sign-in" contract.
        await _account.createEmailToken(userId: userId, email: email);
      } else {
        // `createPhoneToken` (`account.dart:1283`) mirrors `createEmailToken`.
        await _account.createPhoneToken(userId: userId, phone: phone!);
      }
      _pendingOtpUserId = userId;
    } on AppwriteException catch (error) {
      throw _wrap('Failed to send OTP', error);
    }
  }

  @override
  Future<AppBoxKitAuthSession> confirmOtp({
    String? email,
    String? phone,
    required String code,
  }) async {
    final identity = email ?? phone;
    final userId = identity != null
        ? _idService.canonicalId(kAppBoxKitAuthUsersTable, identity.toLowerCase())
        : _pendingOtpUserId;
    if (userId == null) {
      throw const AppBoxKitAuthException(
        'confirmOtp has no pending identity — call requestOtp first, or '
        'pass the same email/phone used there',
        code: 'invalid-otp-target',
      );
    }
    try {
      // `createSession(userId:, secret:)` (`account.dart:966`) completes
      // any token-issued flow (email/phone token here) — `secret` is the
      // code the user was sent.
      await _account.createSession(userId: userId, secret: code);
      final session = await _refreshSession();
      _pendingOtpUserId = null;
      return session;
    } on AppwriteException catch (error) {
      throw _wrap('OTP verification failed', error);
    }
  }

  @override
  Future<AppBoxKitAuthSession> signInWithGoogle() =>
      _signInWithOAuth(enums.OAuthProvider.google);

  @override
  Future<AppBoxKitAuthSession> signInWithApple() =>
      _signInWithOAuth(enums.OAuthProvider.apple);

  Future<AppBoxKitAuthSession> _signInWithOAuth(enums.OAuthProvider provider) async {
    try {
      // `createOAuth2Token` (`account.dart:1234`) and `createOAuth2Session`
      // (`account.dart:898`) both end by calling the client's `webAuth`
      // helper (`client_io.dart:473`, `client_browser.dart`), which drives
      // the actual browser flow via `FlutterWebAuth2.authenticate` using
      // the `appwrite-callback-<PROJECT_ID>` scheme, then parses `key`/
      // `secret` off the redirect and saves them straight into the SDK's
      // own cookie jar as a live session. Despite the "Token" name — whose
      // REST docs describe returning a userId+secret pair for a *separate*
      // `createSession` call — the Flutter SDK's `webAuth` never exposes
      // that pair to app code and completes the session itself; both
      // methods behave identically in this SDK. `Account.get()` right
      // after reflects the newly-authenticated user with no further call
      // needed. (Verified by reading `webAuth`'s body; if a future SDK
      // version changes this and `get()` 401s post-flow,
      // `createOAuth2Session` is the REST-accurate fallback.)
      await _account.createOAuth2Token(provider: provider);
      return await _refreshSession();
    } on AppwriteException catch (error) {
      throw _wrap('${provider.value} sign-in failed', error);
    }
  }

  @override
  Future<AppBoxKitAuthSession> signInAnonymously() async {
    try {
      // `createAnonymousSession` (`account.dart:812`) already returns a
      // `models.Session`, but this still funnels through `_refreshSession`
      // (`Account.get()`) for the same one-mapping-path reason every other
      // method does.
      await _account.createAnonymousSession();
      return await _refreshSession();
    } on AppwriteException catch (error) {
      throw _wrap('Anonymous sign-in failed', error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      // `'current'` targets the active session without needing its id
      // (`account.dart:1032` doc comment).
      await _account.deleteSession(sessionId: 'current');
      _session$.add(null);
    } on AppwriteException catch (error) {
      if (error.code == 401) {
        // The session was already gone server-side — the goal state is
        // reached; report signed-out instead of failing with a stale
        // session$ still claiming signed-in.
        _session$.add(null);
        return;
      }
      throw _wrap('Sign-out failed', error);
    }
  }

  @override
  Future<void> dispose() async {
    await _session$.close();
  }

  // -- Mapping -----------------------------------------------------------

  Future<AppBoxKitAuthSession> _refreshSession() async {
    final user = await _account.get();
    final session = _sessionFromUser(user);
    _session$.add(session);
    return session;
  }

  AppBoxKitAuthSession _sessionFromUser(models.User user) {
    return AppBoxKitAuthSession(
      user: _mapUser(user),
      // Appwrite's Flutter client sessions are cookie/internal — `webAuth`
      // stores the session secret in the SDK's own cookie jar
      // (`client_io.dart:492`-`498`) and every subsequent `client.call`
      // sends it automatically; there is no bearer token this service could
      // hand a caller. `models.Session.secret` (the closest field) is the
      // cookie value itself, not a token meant to be carried outside the
      // SDK, so [AppBoxKitAuthSession.accessToken] stays null here per its own
      // doc comment ("null on the seed backend... exist for hosts that must
      // hand a JWT to something the kit doesn't wrap" — Appwrite has
      // nothing that qualifies).
      accessToken: null,
      // `Account.get()` returns `models.User`, not `models.Session` — the
      // session's `expire` timestamp (`models/session.dart`) is only
      // available from `Account.getSession`/`createXSession` responses.
      // Every sign-in path here intentionally funnels through `get()` alone
      // for one mapping code path, so `expiresAt` is left null rather than
      // adding a second round trip only some callers would need.
      expiresAt: null,
    );
  }

  AppBoxKitAuthUser _mapUser(models.User user) {
    final email = user.email.isEmpty ? null : user.email;
    final phone = user.phone.isEmpty ? null : user.phone;
    return AppBoxKitAuthUser(
      // `user.$id` is already the canonical id for every sign-up/OTP path
      // here (we always pass `idService.canonicalId(...)` as `userId`), and
      // a no-op pass-through for it (`AppBoxKitIdService.isUuid`). For
      // Appwrite-assigned ids (OAuth, anonymous — where this service never
      // supplies a `userId`), canonicalizing still yields a stable,
      // deterministic id derived from that Appwrite id, so identity stays
      // consistent across sessions even though it differs from `$id`.
      id: _idService.canonicalId(kAppBoxKitAuthUsersTable, user.$id),
      email: email,
      phone: phone,
      displayName: user.name.isEmpty ? null : user.name,
      // Appwrite's `models.User` has no `isAnonymous` field; an anonymous
      // account is, by construction, one with neither email nor phone set
      // (`createAnonymousSession` never collects either) — this is a
      // heuristic, not an SDK-documented flag.
      isAnonymous: email == null && phone == null,
      metadata: user.prefs.data,
    );
  }

  AppBoxKitAuthException _wrap(String message, AppwriteException error) {
    final detail = error.message;
    return AppBoxKitAuthException(
      detail == null || detail.isEmpty ? message : detail,
      code: error.code?.toString(),
      cause: error,
    );
  }
}
