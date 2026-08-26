import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:arxa_kit_auth/arxa_kit_auth.dart';

AuthorizationCredentialAppleID _credential({
  String? userIdentifier = 'apple-sub-123',
  String? email,
  String? givenName,
  String? familyName,
  String? identityToken = 'apple.jwt.token',
  String authorizationCode = 'apple-auth-code',
}) =>
    AuthorizationCredentialAppleID(
      userIdentifier: userIdentifier,
      email: email,
      givenName: givenName,
      familyName: familyName,
      identityToken: identityToken,
      authorizationCode: authorizationCode,
      state: null,
    );

/// Builds a provider whose platform boundary is scripted: [available] for the
/// capability probe, [onFetch] for the credential call (return or throw).
ArxaKitAppleSignInProvider _provider({
  bool available = true,
  required Future<AuthorizationCredentialAppleID> Function(
    List<AppleIDAuthorizationScopes> scopes,
    String? nonce,
  ) onFetch,
  String nonce = 'fixed-raw-nonce',
}) =>
    ArxaKitAppleSignInProvider(
      isAvailable: () async => available,
      getCredential: ({required scopes, nonce, webAuthenticationOptions}) =>
          onFetch(scopes, nonce),
      rawNonce: () => nonce,
    );

void main() {
  group('ArxaKitAppleSignInProvider', () {
    test('kit.auth.oauth-apple — id is apple', () {
      expect(_provider(onFetch: (_, __) => throw UnimplementedError()).id,
          'apple');
    });

    test('kit.auth.oauth-apple — first authorization: maps email, name, tokens, and nonce hash',
        () async {
      List<AppleIDAuthorizationScopes>? seenScopes;
      String? seenNonce;
      final provider = _provider(onFetch: (scopes, nonce) async {
        seenScopes = scopes;
        seenNonce = nonce;
        return _credential(
          email: 'relay@privaterelay.appleid.com',
          givenName: 'Ada',
          familyName: 'L',
        );
      });

      final res = await provider.signIn();

      expect(res, isA<ArxaKitAuthSuccess>());
      final session = (res as ArxaKitAuthSuccess).session;
      expect(session.user.id, 'apple-sub-123');
      expect(session.user.email, 'relay@privaterelay.appleid.com');
      expect(session.user.displayName, 'Ada L');
      expect(session.accessToken, 'apple.jwt.token'); // identityToken handoff
      expect(session.refreshToken, 'apple-auth-code'); // authorizationCode
      expect(session.user.metadata['rawNonce'], 'fixed-raw-nonce');
      // The request carries the SHA-256 hash of the raw nonce, never the raw.
      expect(seenNonce,
          sha256.convert(utf8.encode('fixed-raw-nonce')).toString());
      expect(seenScopes, contains(AppleIDAuthorizationScopes.email));
      expect(seenScopes, contains(AppleIDAuthorizationScopes.fullName));
    });

    test('kit.auth.oauth-apple — repeat authorization: null email/name is normal, id stays stable',
        () async {
      final provider = _provider(
        onFetch: (_, __) async => _credential(), // no email/name
      );

      final res = await provider.signIn();

      expect(res, isA<ArxaKitAuthSuccess>());
      final user = (res as ArxaKitAuthSuccess).user;
      expect(user.id, 'apple-sub-123');
      expect(user.email, isNull);
      expect(user.displayName, isNull);
    });

    test('kit.auth.oauth-apple — cancellation → ArxaKitAuthFailure(cancelled), not an exception', () async {
      final provider = _provider(
        onFetch: (_, __) => throw const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.canceled,
          message: 'user cancelled',
        ),
      );

      final res = await provider.signIn();

      expect(res, isA<ArxaKitAuthFailure>());
      expect((res as ArxaKitAuthFailure).reason, ArxaKitAuthFailureReason.cancelled);
    });

    test('kit.auth.oauth-apple — capability probe failure → operationNotAllowed', () async {
      var fetchCalled = false;
      final provider = _provider(
        available: false,
        onFetch: (_, __) {
          fetchCalled = true;
          throw UnimplementedError();
        },
      );

      final res = await provider.signIn();

      expect(res, isA<ArxaKitAuthFailure>());
      expect((res as ArxaKitAuthFailure).reason,
          ArxaKitAuthFailureReason.operationNotAllowed);
      expect(fetchCalled, isFalse); // never reaches the platform flow
    });

    test('kit.auth.oauth-apple — not-supported exception → operationNotAllowed', () async {
      final provider = _provider(
        onFetch: (_, __) =>
            throw const SignInWithAppleNotSupportedException(
          message: 'iOS < 13',
        ),
      );

      final res = await provider.signIn();

      expect(res, isA<ArxaKitAuthFailure>());
      expect((res as ArxaKitAuthFailure).reason,
          ArxaKitAuthFailureReason.operationNotAllowed);
    });

    test('kit.auth.oauth-apple — other authorization error → unknown, cause retained', () async {
      const error = SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.failed,
        message: 'something failed',
      );
      final provider = _provider(onFetch: (_, __) => throw error);

      final res = await provider.signIn();

      expect(res, isA<ArxaKitAuthFailure>());
      expect((res as ArxaKitAuthFailure).reason, ArxaKitAuthFailureReason.unknown);
      expect(res.message, 'something failed');
      expect(identical(res.cause, error), isTrue);
    });
  });
}
