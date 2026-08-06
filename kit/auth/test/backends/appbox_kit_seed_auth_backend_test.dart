import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_auth/appbox_kit_auth.dart';

void main() {
  group('AppBoxKitSeedAuthBackend (tier1 spec port)', () {
    test('kit.auth.seed-backend — seeds the deterministic showcase accounts', () {
      final backend = AppBoxKitSeedAuthBackend();
      final users = backend.seedUsers();
      expect(users['seed_alice']?['email'], 'alice@showcase.app');
      expect(users['seed_bob']?['email'], 'bob@showcase.app');
      // Passwords are never exposed.
      expect(users['seed_alice']!.containsKey('password'), isFalse);
    });

    test('kit.auth.seed-backend — valid sign-in succeeds with user id + fresh token', () async {
      final backend = AppBoxKitSeedAuthBackend();
      final res = await backend.signIn(const AppBoxKitEmailPasswordCredentials(
        email: 'alice@showcase.app',
        password: 'seed-alice',
      ));
      expect(res, isA<AppBoxKitAuthSuccess>());
      final success = res as AppBoxKitAuthSuccess;
      expect(success.user.id, 'seed_alice');
      expect(success.user.email, 'alice@showcase.app');
      expect(success.session.accessToken, isNotNull);
      expect(backend.currentUser?.email, 'alice@showcase.app');
      expect(backend.currentUserFor('seed_alice')?.email, 'alice@showcase.app');
    });

    test('kit.auth.seed-backend — wrong password → invalidCredentials', () async {
      final backend = AppBoxKitSeedAuthBackend();
      final res = await backend.signIn(const AppBoxKitEmailPasswordCredentials(
        email: 'alice@showcase.app',
        password: 'nope',
      ));
      expect(res, isA<AppBoxKitAuthFailure>());
      expect((res as AppBoxKitAuthFailure).reason, AppBoxKitAuthFailureReason.invalidCredentials);
      expect(res.message, 'wrong password');
    });

    test('kit.auth.seed-backend — unknown user → userNotFound', () async {
      final backend = AppBoxKitSeedAuthBackend();
      final res = await backend.signIn(const AppBoxKitEmailPasswordCredentials(
        email: 'nobody@showcase.app',
        password: 'x',
      ));
      expect(res, isA<AppBoxKitAuthFailure>());
      expect((res as AppBoxKitAuthFailure).reason, AppBoxKitAuthFailureReason.userNotFound);
      expect(res.message, 'unknown user');
    });

    test('kit.auth.seed-backend — signOut clears the session and emits null', () async {
      final backend = AppBoxKitSeedAuthBackend();
      await backend.signIn(const AppBoxKitEmailPasswordCredentials(
        email: 'alice@showcase.app',
        password: 'seed-alice',
      ));
      final states = <AppBoxKitAuthUser?>[];
      final sub = backend.authStateChanges.listen(states.add);
      await backend.signOut();
      expect(backend.currentUser, isNull);
      expect(backend.currentUserFor('seed_alice'), isNull);
      // The stream replays the current state on listen, then the sign-out.
      await Future<void>.delayed(Duration.zero);
      expect(states.last, isNull);
      await sub.cancel();
    });

    test('kit.auth.seed-backend — signUp creates a new user + session; duplicate is rejected; '
        'the new user can sign in independently', () async {
      final backend = AppBoxKitSeedAuthBackend();
      final res = await backend.signUp(const AppBoxKitEmailPasswordCredentials(
        email: 'carol@showcase.app',
        password: 'pw-carol',
      ));
      expect(res, isA<AppBoxKitAuthSuccess>());
      final success = res as AppBoxKitAuthSuccess;
      expect(success.session.accessToken, isNotNull);
      final newUid = success.user.id;
      expect(backend.currentUserFor(newUid)?.email, 'carol@showcase.app');

      final dup = await backend.signUp(const AppBoxKitEmailPasswordCredentials(
        email: 'carol@showcase.app',
        password: 'x',
      ));
      expect(dup, isA<AppBoxKitAuthFailure>());
      expect(
        (dup as AppBoxKitAuthFailure).reason,
        AppBoxKitAuthFailureReason.emailAlreadyInUse,
      );

      await backend.signOut();
      final signIn = await backend.signIn(const AppBoxKitEmailPasswordCredentials(
        email: 'carol@showcase.app',
        password: 'pw-carol',
      ));
      expect(signIn, isA<AppBoxKitAuthSuccess>());
    });

    test('kit.auth.seed-backend — token refresh rotates: old token dies, bogus token fails', () async {
      final backend = AppBoxKitSeedAuthBackend();
      final auth = await backend.signIn(const AppBoxKitEmailPasswordCredentials(
        email: 'bob@showcase.app',
        password: 'seed-bob',
      )) as AppBoxKitAuthSuccess;
      final token = auth.session.accessToken!;

      final refreshed = await backend.refreshToken(token);
      expect(refreshed, isA<AppBoxKitAuthSuccess>());
      final rotated = (refreshed as AppBoxKitAuthSuccess).session.accessToken!;
      expect(rotated, isNot(token));

      final oldDead = await backend.refreshToken(token);
      expect(oldDead, isA<AppBoxKitAuthFailure>());
      expect((oldDead as AppBoxKitAuthFailure).reason, AppBoxKitAuthFailureReason.tokenExpired);

      final bogus = await backend.refreshToken('bogus');
      expect(bogus, isA<AppBoxKitAuthFailure>());
      expect((bogus as AppBoxKitAuthFailure).reason, AppBoxKitAuthFailureReason.tokenExpired);
    });

    test('kit.auth.seed-backend — tokens mint monotonically (tok_1, tok_2, …)', () async {
      final backend = AppBoxKitSeedAuthBackend();
      final a = await backend.signIn(const AppBoxKitEmailPasswordCredentials(
        email: 'alice@showcase.app',
        password: 'seed-alice',
      )) as AppBoxKitAuthSuccess;
      final b = await backend.signIn(const AppBoxKitEmailPasswordCredentials(
        email: 'bob@showcase.app',
        password: 'seed-bob',
      )) as AppBoxKitAuthSuccess;
      expect(a.session.accessToken, 'tok_1');
      expect(b.session.accessToken, 'tok_2');
    });

    test('kit.auth.seed-backend — sign-up uids mint monotonically (user_1, user_2, …)', () async {
      final backend = AppBoxKitSeedAuthBackend();
      final a = await backend.signUp(const AppBoxKitEmailPasswordCredentials(
        email: 'a@showcase.app',
        password: 'pw',
      )) as AppBoxKitAuthSuccess;
      final b = await backend.signUp(const AppBoxKitEmailPasswordCredentials(
        email: 'b@showcase.app',
        password: 'pw',
      )) as AppBoxKitAuthSuccess;
      expect(a.user.id, 'user_1');
      expect(b.user.id, 'user_2');
    });

    test('kit.auth.seed-backend — Apple/Google sign-in resolve deterministic demo identities', () async {
      final backend = AppBoxKitSeedAuthBackend();
      final apple = await backend.signInWithApple();
      expect(apple, isA<AppBoxKitAuthSuccess>());
      expect((apple as AppBoxKitAuthSuccess).user.id, 'apple_demo_user');
      expect(apple.user.email, 'relay@apple.example');
      expect(apple.user.metadata['provider'], 'apple');

      final google = await backend.signInWithGoogle();
      expect(google, isA<AppBoxKitAuthSuccess>());
      expect((google as AppBoxKitAuthSuccess).user.id, 'google_demo_user');
      expect(google.user.email, 'demo@google.example');
      expect(google.user.metadata['provider'], 'google');

      // Repeat sign-in resolves the same identity.
      final again = await backend.signInWithApple() as AppBoxKitAuthSuccess;
      expect(again.user.id, 'apple_demo_user');
    });

    test('kit.auth.seed-backend — authStateChanges replays current user then live changes', () async {
      final backend = AppBoxKitSeedAuthBackend();
      final emitted = <AppBoxKitAuthUser?>[];
      final sub = backend.authStateChanges.listen(emitted.add);
      // Let the async* replay land and the generator subscribe to the live
      // controller before mutating (broadcast streams do not buffer).
      await Future<void>.delayed(Duration.zero);
      await backend.signIn(const AppBoxKitEmailPasswordCredentials(
        email: 'alice@showcase.app',
        password: 'seed-alice',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(2));
      expect(emitted[0], isNull); // replayed signed-out state
      expect(emitted[1]?.id, 'seed_alice');
      await sub.cancel();
    });

    test('kit.auth.seed-backend — use after dispose throws StateError', () async {
      final backend = AppBoxKitSeedAuthBackend();
      await backend.dispose();
      expect(
        () => backend.signIn(const AppBoxKitEmailPasswordCredentials(
          email: 'alice@showcase.app',
          password: 'seed-alice',
        )),
        throwsStateError,
      );
    });
  });
}
