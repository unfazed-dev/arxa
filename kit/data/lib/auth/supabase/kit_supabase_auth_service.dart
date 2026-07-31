/// [KitAuthService] backed by Supabase Auth.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/kit_data_config.dart';
import '../../ids/kit_id_service.dart';
import '../kit_auth_service.dart';
import '../kit_auth_types.dart';

/// Supabase implementation of [KitAuthService].
///
/// `SupabaseClient.auth` is a `GoTrueClient` (`package:gotrue`, resolved as
/// `2.26.0` under `supabase_flutter: 2.16.0` — verified against
/// `gotrue-2.26.0/lib/src/gotrue_client.dart`); every SDK call cited below
/// was verified against that installed source.
///
/// Constraints:
/// - [session$] owns a [BehaviorSubject], seeded in [initialize]. This is
///   NOT a repository-layer double-buffer violation: `GoTrueClient
///   .onAuthStateChange` (`gotrue_client.dart:134`) is a broadcast stream of
///   *events*, not a value stream with replay, so a late listener would get
///   nothing until the next auth change without a subject of our own to
///   reseed it — that's the gap this subject exists to close, not a
///   redundant wrapper around something that already replays.
/// - `onAuthStateChange`'s controller also carries internal errors:
///   `GoTrueClient.notifyException` (`gotrue_client.dart:1585`) routes
///   refresh-token and similar failures through `addError` on that same
///   stream. Per Supabase's own guidance, an unhandled stream error becomes
///   an uncaught zone error and crashes the app, so the subscription below
///   always supplies an `onError` that forwards into this service's subject
///   via `addError` rather than letting it propagate unhandled.
class KitSupabaseAuthService implements KitAuthService {
  KitSupabaseAuthService({
    required SupabaseClient client,
    required KitAuthConfig config,
    required KitIdService idService,
  })  : _client = client,
        _config = config,
        _idService = idService;

  final SupabaseClient _client;
  final KitAuthConfig _config;
  final KitIdService _idService;

  final BehaviorSubject<KitAuthSession?> _session$ =
      BehaviorSubject<KitAuthSession?>();
  StreamSubscription<AuthState>? _authSub;

  /// `GoogleSignIn.instance.initialize` must be called exactly once and
  /// awaited before any other method on the singleton
  /// (`google_sign_in-7.2.0/lib/google_sign_in.dart`, `GoogleSignIn
  /// .initialize` doc comment) — this guards that.
  bool _googleInitialized = false;

  /// Subscribes to `onAuthStateChange` and seeds [session$] with the
  /// current session. Must be awaited before this service is registered —
  /// matches every other backend's `initialize()` contract in
  /// `kit_data.dart`.
  Future<void> initialize() async {
    _session$.add(_mapSession(_client.auth.currentSession));
    _authSub = _client.auth.onAuthStateChange.listen(
      (state) => _session$.add(_mapSession(state.session)),
      onError: (Object error, StackTrace stackTrace) {
        _session$.addError(error, stackTrace);
      },
    );
  }

  @override
  Stream<KitAuthSession?> get session$ => _session$.stream;

  @override
  KitAuthSession? get currentSession => _session$.valueOrNull;

  /// Uniform error surface shared by every method: [KitAuthException]s pass
  /// through untouched; each SDK's exception type is wrapped with its own
  /// message/code; anything else gets [fallbackMessage]. One catch ladder
  /// instead of eight copies.
  Future<T> _guard<T>(String fallbackMessage, Future<T> Function() body) async {
    try {
      return await body();
    } on KitAuthException {
      rethrow;
    } on AuthException catch (error) {
      throw KitAuthException(error.message, code: error.code, cause: error);
    } on GoogleSignInException catch (error) {
      throw KitAuthException(
        error.description ?? fallbackMessage,
        code: error.code.name,
        cause: error,
      );
    } on SignInWithAppleException catch (error) {
      throw KitAuthException(fallbackMessage, cause: error);
    } catch (error) {
      throw KitAuthException(fallbackMessage, cause: error);
    }
  }

  @override
  Future<KitAuthSession> signUpWithEmailPassword({
    required String email,
    required String password,
  }) =>
      _guard('Sign-up failed', () async {
        final response = await _client.auth.signUp(
          email: email,
          password: password,
        );
        final session = response.session;
        if (session == null) {
          // gotrue_client.dart:232 — `signUp` only returns a session when the
          // project has autoconfirm ON. With email confirmation required it
          // returns a user but no session; the caller must wait for the
          // confirmation link before a session exists.
          throw const KitAuthException(
            'Sign-up succeeded but requires email confirmation before a '
            'session exists.',
            code: 'email-confirmation-required',
          );
        }
        return _mapSession(session)!;
      });

  @override
  Future<KitAuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) =>
      _guard('Sign-in failed', () async {
        final response = await _client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        return _requireSession(response.session, 'no-session');
      });

  /// Maps [session], throwing [KitAuthException] with [code] when the SDK
  /// handed back none — shared by every path that must end signed-in.
  KitAuthSession _requireSession(Session? session, String code) {
    final mapped = _mapSession(session);
    if (mapped == null) {
      throw KitAuthException('Sign-in returned no session', code: code);
    }
    return mapped;
  }

  @override
  Future<void> requestOtp({String? email, String? phone}) async {
    if ((email == null) == (phone == null)) {
      // Not a `assert` — asserts strip in release builds, and this
      // constraint must hold in production too.
      throw const KitAuthException(
        'requestOtp requires exactly one of email or phone',
        code: 'invalid-otp-target',
      );
    }
    await _guard(
      'Failed to send OTP',
      () => _client.auth.signInWithOtp(email: email, phone: phone),
    );
  }

  @override
  Future<KitAuthSession> confirmOtp({
    String? email,
    String? phone,
    required String code,
  }) async {
    if ((email == null) == (phone == null)) {
      throw const KitAuthException(
        'confirmOtp requires exactly one of email or phone',
        code: 'invalid-otp-target',
      );
    }
    return _guard('OTP verification failed', () async {
      final response = await _client.auth.verifyOTP(
        email: email,
        phone: phone,
        token: code,
        // gotrue's `OtpType` enum (`gotrue_client.dart` /
        // `constants.dart:85`) distinguishes `email` from `sms` — phone OTP
        // verification is always `OtpType.sms`, matching the SDK's own
        // `signInWithOtp(phone:)` → `verifyOTP` pairing.
        type: email != null ? OtpType.email : OtpType.sms,
      );
      return _requireSession(response.session, 'otp-no-session');
    });
  }

  @override
  Future<KitAuthSession> signInWithGoogle() =>
      _guard('Google sign-in failed', () async {
        if (!_googleInitialized) {
        await GoogleSignIn.instance.initialize(
          clientId: _config.googleClientId,
          serverClientId: _config.googleServerClientId,
        );
        _googleInitialized = true;
      }
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const ['email'],
      );
      // v7 moved the ID token onto `GoogleSignInAccount.authentication`
      // (`google_sign_in-7.2.0/lib/src/token_types.dart`,
      // `GoogleSignInAuthentication`) — it no longer carries an access
      // token; that moved behind a *separate* authorization request via
      // `authorizationClient` (`google_sign_in.dart`,
      // `GoogleSignInAuthorizationClient`).
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const KitAuthException(
          'Google sign-in did not return an ID token',
          code: 'google-missing-id-token',
        );
      }
      // Best-effort, non-prompting access-token fetch: `signInWithIdToken`
      // only requires `accessToken` when the ID token itself carries an
      // `at_hash` claim (`gotrue_client.dart:454`); `authorizationForScopes`
      // returns `null` rather than prompting when it can't satisfy the
      // request silently (`token_types.dart`,
      // `GoogleSignInAuthorizationClient.authorizationForScopes` doc
      // comment), so a `null` accessToken here is an expected, non-fatal
      // outcome, not a failure.
      final authorization = await account.authorizationClient
          .authorizationForScopes(const ['email']);
      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization?.accessToken,
      );
      return _requireSession(response.session, 'google-no-session');
    });

  @override
  Future<KitAuthSession> signInWithApple() =>
      _guard('Apple sign-in failed', () async {
      // `client.auth.generateRawNonce()` is an extension method on
      // `GoTrueClient` (`supabase_flutter-2.16.0/lib/src/supabase_auth.dart`,
      // `extension GoTrueClientSignInProvider`) — the supabase_flutter
      // package's own helper, not hand-rolled here.
      final rawNonce = _client.auth.generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const KitAuthException(
          'Apple sign-in did not return an identity token',
          code: 'apple-missing-id-token',
        );
      }
      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
      final session = _requireSession(response.session, 'apple-no-session');
      // Apple only returns givenName/familyName on the FIRST authorization
      // between this app and the user's Apple ID
      // (`sign_in_with_apple_platform_interface-2.0.0/lib/authorization_credential.dart`,
      // `AuthorizationCredentialAppleID.givenName`/`.familyName` doc
      // comments) — persist them now, since a later sign-in won't hand them
      // back. Also written under `full_name` so `_mapUser`'s
      // `displayName` fallback (`metadata['full_name'] ?? metadata['name']`)
      // actually surfaces it, instead of only under keys nothing reads.
      if (credential.givenName != null || credential.familyName != null) {
        final fullName = [credential.givenName, credential.familyName]
            .whereType<String>()
            .join(' ');
        try {
          await _client.auth.updateUser(
            UserAttributes(
              data: {
                if (credential.givenName != null)
                  'given_name': credential.givenName,
                if (credential.familyName != null)
                  'family_name': credential.familyName,
                if (fullName.isNotEmpty) 'full_name': fullName,
              },
            ),
          );
        } catch (_) {
          // Non-critical: the session below is already live
          // (`signInWithIdToken` already fired `notifyAllSubscribers
          // (signedIn)`, so `session$` already reflects it) — a transient
          // failure to persist the name must not turn a successful sign-in
          // into a thrown exception. Same "best-effort, not fatal"
          // treatment as the Google access-token fetch above.
        }
      }
      return session;
    });

  @override
  Future<KitAuthSession> signInAnonymously() =>
      _guard('Anonymous sign-in failed', () async {
        final response = await _client.auth.signInAnonymously();
        return _requireSession(response.session, 'anonymous-no-session');
      });

  @override
  Future<void> signOut() =>
      _guard('Sign-out failed', () => _client.auth.signOut());

  @override
  Future<void> dispose() async {
    await _authSub?.cancel();
    await _session$.close();
  }

  // -- Mapping ---------------------------------------------------------

  KitAuthSession? _mapSession(Session? session) {
    if (session == null) return null;
    return KitAuthSession(
      user: _mapUser(session.user),
      accessToken: session.accessToken,
      // `Session.expiresAt` (`gotrue-2.26.0/lib/src/types/session.dart`) is
      // the Unix timestamp in *seconds*, parsed from the access token's
      // `exp` JWT claim — multiply by 1000 for
      // `DateTime.fromMillisecondsSinceEpoch`, per that field's own doc
      // comment.
      expiresAt: session.expiresAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000),
    );
  }

  KitAuthUser _mapUser(User user) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final email = user.email;
    final phone = user.phone;
    return KitAuthUser(
      // Supabase uids are already UUIDs; `canonicalId` no-ops on UUID input
      // (`KitIdService.isUuid`), so this stays on the same code path as
      // every other id in the layer instead of a bespoke passthrough.
      id: _idService.canonicalId(kKitAuthUsersTable, user.id),
      // gotrue reports absent email/phone as empty strings, not null —
      // normalize so KitAuthUser means the same thing on every backend.
      email: email == null || email.isEmpty ? null : email,
      phone: phone == null || phone.isEmpty ? null : phone,
      displayName: (metadata['full_name'] ?? metadata['name']) as String?,
      isAnonymous: user.isAnonymous,
      metadata: metadata,
    );
  }
}
