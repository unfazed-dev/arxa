import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_auth/arxa_kit_auth.dart';

void main() {
  group('ArxaKitSeedAuthBackend (tier1 spec port)', () {
    test('kit.auth.seed-backend — seeds the deterministic showcase accounts', () {
      final backend = ArxaKitSeedAuthBackend();
      final users = backend.seedUsers();
      expect(users['seed_alice']?['email'], 'alice@showcase.app');
      expect(users['seed_bob']?['email'], 'bob@showcase.app');
      // Passwords are never exposed.
      expect(users['seed_alice']!.containsKey('password'), isFalse);
    });

    test('kit.auth.seed-backend — valid sign-in succeeds with user id + fresh token', () async {
      final backend = ArxaKitSeedAuthBackend();
      final res = await backend.signIn(const ArxaKitEmailPasswordCredentials(
        email: 'alice@showcase.app',
        password: 'seed-alice',
      ));
      expect(res, isA<ArxaKitAuthSuccess>());
      final success = res as ArxaKitAuthSuccess;
      expect(success.user.id, 'seed_alice');
      expect(success.user.email, 'alice@showcase.app');
      expect(success.session.accessToken, isNotNull);
      expect(backend.currentUser?.email, 'alice@showcase.app');
      expect(backend.currentUserFor('seed_alice')?.email, 'alice@showcase.app');
    });

    test('kit.auth.seed-backend — wrong password → invalidCredentials', () async {
      final backend = ArxaKitSeedAuthBackend();
      final res = await backend.signIn(const ArxaKitEmailPasswordCredentials(
        email: 'alice@showcase.app',
        password: 'nope',
      ));
      expect(res, isA<ArxaKitAuthFailure>());
      expect((res as ArxaKitAuthFailure).reason, ArxaKitAuthFailureReason.invalidCredentials);
      expect(res.message, 'wrong password');
    });

    test('kit.auth.seed-backend — unknown user → userNotFound', () async {
      final backend = ArxaKitSeedAuthBackend();
      final res = await backend.signIn(const ArxaKitEmailPasswordCredentials(
        email: 'nobody@showcase.app',
        password: 'x',
      ));
      expect(res, isA<ArxaKitAuthFailure>());
      expect((res as ArxaKitAuthFailure).reason, ArxaKitAuthFailureReason.userNotFound);
      expect(res.message, 'unknown user');
    });

    test('kit.auth.seed-backend — signOut clears the session and emits null', () async {
      final backend = ArxaKitSeedAuthBackend();
      await backend.signIn(const ArxaKitEmailPasswordCredentials(
        email: 'alice@showcase.app',
        password: 'seed-alice',
      ));
      final states = <ArxaKitAuthUser?>[];
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
      final backend = ArxaKitSeedAuthBackend();
      final res = await backend.signUp(const ArxaKitEmailPasswordCredentials(
        email: 'carol@showcase.app',
        password: 'pw-carol',
      ));
      expect(res, isA<ArxaKitAuthSuccess>());
      final success = res as ArxaKitAuthSuccess;
      expect(success.session.accessToken, isNotNull);
      final newUid = success.user.id;
      expect(backend.currentUserFor(newUid)?.email, 'carol@showcase.app');

      final dup = await backend.signUp(const ArxaKitEmailPasswordCredentials(
        email: 'carol@showcase.app',
        password: 'x',
      ));
      expect(dup, isA<ArxaKitAuthFailure>());
      expect(
        (dup as ArxaKitAuthFailure).reason,
        ArxaKitAuthFailureReason.emailAlreadyInUse,
      );

      await backend.signOut();
      final signIn = await backend.signIn(const ArxaKitEmailPasswordCredentials(
        email: 'carol@showcase.app',
        password: 'pw-carol',
      ));
      expect(signIn, isA<ArxaKitAuthSuccess>());
    });

    test('kit.auth.seed-backend — token refresh rotates: old token dies, bogus token fails', () async {
      final backend = ArxaKitSeedAuthBackend();
      final auth = await backend.signIn(const ArxaKitEmailPasswordCredentials(
        email: 'bob@showcase.app',
        password: 'seed-bob',
      )) as ArxaKitAuthSuccess;
      final token = auth.session.accessToken!;

      final refreshed = await backend.refreshToken(token);
      expect(refreshed, isA<ArxaKitAuthSuccess>());
      final rotated = (refreshed as ArxaKitAuthSuccess).session.accessToken!;
      expect(rotated, isNot(token));

      final oldDead = await backend.refreshToken(token);
      expect(oldDead, isA<ArxaKitAuthFailure>());
      expect((oldDead as ArxaKitAuthFailure).reason, ArxaKitAuthFailureReason.tokenExpired);

      final bogus = await backend.refreshToken('bogus');
      expect(bogus, isA<ArxaKitAuthFailure>());
      expect((bogus as ArxaKitAuthFailure).reason, ArxaKitAuthFailureReason.tokenExpired);
    });

    test('kit.auth.seed-backend — tokens mint monotonically (tok_1, tok_2, …)', () async {
      final backend = ArxaKitSeedAuthBackend();
      final a = await backend.signIn(const ArxaKitEmailPasswordCredentials(
        email: 'alice@showcase.app',
        password: 'seed-alice',
      )) as ArxaKitAuthSuccess;
      final b = await backend.signIn(const ArxaKitEmailPasswordCredentials(
        email: 'bob@showcase.app',
        password: 'seed-bob',
      )) as ArxaKitAuthSuccess;
      expect(a.session.accessToken, 'tok_1');
      expect(b.session.accessToken, 'tok_2');
    });

    test('kit.auth.seed-backend — sign-up uids mint monotonically (user_1, user_2, …)', () async {
      final backend = ArxaKitSeedAuthBackend();
      final a = await backend.signUp(const ArxaKitEmailPasswordCredentials(
        email: 'a@showcase.app',
        password: 'pw',
      )) as ArxaKitAuthSuccess;
      final b = await backend.signUp(const ArxaKitEmailPasswordCredentials(
        email: 'b@showcase.app',
        password: 'pw',
      )) as ArxaKitAuthSuccess;
      expect(a.user.id, 'user_1');
      expect(b.user.id, 'user_2');
    });

    test('kit.auth.seed-backend — Apple/Google sign-in resolve deterministic demo identities', () async {
      final backend = ArxaKitSeedAuthBackend();
      final apple = await backend.signInWithApple();
      expect(apple, isA<ArxaKitAuthSuccess>());
      expect((apple as ArxaKitAuthSuccess).user.id, 'apple_demo_user');
      expect(apple.user.email, 'relay@apple.example');
      expect(apple.user.metadata['provider'], 'apple');

      final google = await backend.signInWithGoogle();
      expect(google, isA<ArxaKitAuthSuccess>());
      expect((google as ArxaKitAuthSuccess).user.id, 'google_demo_user');
      expect(google.user.email, 'demo@google.example');
      expect(google.user.metadata['provider'], 'google');

      // Repeat sign-in resolves the same identity.
      final again = await backend.signInWithApple() as ArxaKitAuthSuccess;
      expect(again.user.id, 'apple_demo_user');
    });

    test('kit.auth.seed-backend — authStateChanges replays current user then live changes', () async {
      final backend = ArxaKitSeedAuthBackend();
      final emitted = <ArxaKitAuthUser?>[];
      final sub = backend.authStateChanges.listen(emitted.add);
      // Let the async* replay land and the generator subscribe to the live
      // controller before mutating (broadcast streams do not buffer).
      await Future<void>.delayed(Duration.zero);
      await backend.signIn(const ArxaKitEmailPasswordCredentials(
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
      final backend = ArxaKitSeedAuthBackend();
      await backend.dispose();
      expect(
        () => backend.signIn(const ArxaKitEmailPasswordCredentials(
          email: 'alice@showcase.app',
          password: 'seed-alice',
        )),
        throwsStateError,
      );
    });
  });
}
