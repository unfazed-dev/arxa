import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:appbox_kit_auth/appbox_kit_auth.dart';

class MockGoogleSignInPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements GoogleSignInPlatform {}

void main() {
  late MockGoogleSignInPlatform platform;

  setUpAll(() {
    registerFallbackValue(const InitParameters());
    registerFallbackValue(const AuthenticateParameters());
  });

  setUp(() {
    platform = MockGoogleSignInPlatform();
    GoogleSignInPlatform.instance = platform;
    when(() => platform.init(any())).thenAnswer((_) async {});
    when(() => platform.supportsAuthenticate()).thenReturn(true);
  });

  AuthenticationResults results({
    String id = 'google-sub-1',
    String email = 'ada@gmail.com',
    String? displayName = 'Ada',
    String? photoUrl,
    String? idToken = 'google.jwt.token',
  }) =>
      AuthenticationResults(
        user: GoogleSignInUserData(
          id: id,
          email: email,
          displayName: displayName,
          photoUrl: photoUrl,
        ),
        authenticationTokens: AuthenticationTokenData(idToken: idToken),
      );

  group('AppBoxKitGoogleSignInProvider', () {
    test('kit.auth.oauth-google — id is google', () {
      expect(AppBoxKitGoogleSignInProvider().id, 'google');
    });

    test('kit.auth.oauth-google — success: initialize → probe → authenticate, session mapped',
        () async {
      when(() => platform.authenticate(any()))
          .thenAnswer((_) async => results(photoUrl: 'https://x/p.png'));

      final provider = AppBoxKitGoogleSignInProvider(
        clientId: 'ios-client-id',
        serverClientId: 'web-client-id',
      );
      final res = await provider.signIn();

      expect(res, isA<AppBoxKitAuthSuccess>());
      final session = (res as AppBoxKitAuthSuccess).session;
      expect(session.user.id, 'google-sub-1');
      expect(session.user.email, 'ada@gmail.com');
      expect(session.user.displayName, 'Ada');
      expect(session.user.metadata['photoUrl'], 'https://x/p.png');
      expect(session.user.metadata['provider'], 'google');
      expect(session.accessToken, 'google.jwt.token'); // idToken handoff

      final init =
          verify(() => platform.init(captureAny())).captured.single
              as InitParameters;
      expect(init.clientId, 'ios-client-id');
      expect(init.serverClientId, 'web-client-id');
      verify(() => platform.supportsAuthenticate()).called(1);
    });

    test('kit.auth.oauth-google — cancellation → AppBoxKitAuthFailure(cancelled), not an exception', () async {
      when(() => platform.authenticate(any())).thenThrow(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
          description: 'user backed out',
        ),
      );

      final res = await AppBoxKitGoogleSignInProvider().signIn();

      expect(res, isA<AppBoxKitAuthFailure>());
      expect((res as AppBoxKitAuthFailure).reason, AppBoxKitAuthFailureReason.cancelled);
      expect(res.message, 'user backed out');
    });

    test('kit.auth.oauth-google — clientConfigurationError → operationNotAllowed', () async {
      when(() => platform.authenticate(any())).thenThrow(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError,
          description: 'missing serverClientId',
        ),
      );

      final res = await AppBoxKitGoogleSignInProvider().signIn();

      expect(res, isA<AppBoxKitAuthFailure>());
      expect((res as AppBoxKitAuthFailure).reason,
          AppBoxKitAuthFailureReason.operationNotAllowed);
    });

    test('kit.auth.oauth-google — other error codes → unknown, cause retained', () async {
      const error = GoogleSignInException(
        code: GoogleSignInExceptionCode.interrupted,
        description: 'network hiccup',
      );
      when(() => platform.authenticate(any())).thenThrow(error);

      final res = await AppBoxKitGoogleSignInProvider().signIn();

      expect(res, isA<AppBoxKitAuthFailure>());
      expect((res as AppBoxKitAuthFailure).reason, AppBoxKitAuthFailureReason.unknown);
      expect(identical(res.cause, error), isTrue);
    });

    test('kit.auth.oauth-google — platform without authenticate support → operationNotAllowed, '
        'authenticate never called', () async {
      when(() => platform.supportsAuthenticate()).thenReturn(false);

      final res = await AppBoxKitGoogleSignInProvider().signIn();

      expect(res, isA<AppBoxKitAuthFailure>());
      expect((res as AppBoxKitAuthFailure).reason,
          AppBoxKitAuthFailureReason.operationNotAllowed);
      verifyNever(() => platform.authenticate(any()));
    });

    test('kit.auth.oauth-google — scopeHint is forwarded to authenticate', () async {
      when(() => platform.authenticate(any()))
          .thenAnswer((_) async => results());

      await AppBoxKitGoogleSignInProvider(scopeHint: const ['email', 'openid'])
          .signIn();

      final params = verify(() => platform.authenticate(captureAny()))
          .captured
          .single as AuthenticateParameters;
      expect(params.scopeHint, ['email', 'openid']);
    });
  });
}
