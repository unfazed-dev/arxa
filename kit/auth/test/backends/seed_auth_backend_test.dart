import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_auth/appbox_kit_auth.dart';

void main() {
  group('SeedAuthBackend (tier1 spec port)', () {
    test('seeds the deterministic showcase accounts', () {
      final backend = SeedAuthBackend();
      final users = backend.seedUsers();
      expect(users['seed_alice']?['email'], 'alice@showcase.app');
      expect(users['seed_bob']?['email'], 'bob@showcase.app');
      // Passwords are never exposed.
      expect(users['seed_alice']!.containsKey('password'), isFalse);
    });

    test('valid sign-in succeeds with user id + fresh token', () async {
      final backend = SeedAuthBackend();
      final res = await backend.signIn(const EmailPasswordCredentials(
        email: 'alice@showcase.app',
        password: 'seed-alice',
      ));
      expect(res, isA<AuthSuccess>());
      final success = res as AuthSuccess;
      expect(success.user.id, 'seed_alice');
      expect(success.user.email, 'alice@showcase.app');
      expect(success.session.accessToken, isNotNull);
      expect(backend.currentUser?.email, 'alice@showcase.app');
      expect(backend.currentUserFor('seed_alice')?.email, 'alice@showcase.app');
    });

    test('wrong password → invalidCredentials', () async {
      final backend = SeedAuthBackend();
      final res = await backend.signIn(const EmailPasswordCredentials(
        email: 'alice@showcase.app',
        password: 'nope',
      ));
      expect(res, isA<AuthFailure>());
      expect((res as AuthFailure).reason, AuthFailureReason.invalidCredentials);
      expect(res.message, 'wrong password');
    });

    test('unknown user → userNotFound', () async {
      final backend = SeedAuthBackend();
      final res = await backend.signIn(const EmailPasswordCredentials(
        email: 'nobody@showcase.app',
        password: 'x',
      ));
      expect(res, isA<AuthFailure>());
      expect((res as AuthFailure).reason, AuthFailureReason.userNotFound);
      expect(res.message, 'unknown user');
    });

    test('signOut clears the session and emits null', () async {
      final backend = SeedAuthBackend();
      await backend.signIn(const EmailPasswordCredentials(
        email: 'alice@showcase.app',
        password: 'seed-alice',
      ));
      final states = <AuthUser?>[];
      final sub = backend.authStateChanges.listen(states.add);
      await backend.signOut();
      expect(backend.currentUser, isNull);
      expect(backend.currentUserFor('seed_alice'), isNull);
      // The stream replays the current state on listen, then the sign-out.
      await Future<void>.delayed(Duration.zero);
      expect(states.last, isNull);
      await sub.cancel();
    });

    test('signUp creates a new user + session; duplicate is rejected; '
        'the new user can sign in independently', () async {
      final backend = SeedAuthBackend();
      final res = await backend.signUp(const EmailPasswordCredentials(
        email: 'carol@showcase.app',
        password: 'pw-carol',
      ));
      expect(res, isA<AuthSuccess>());
      final success = res as AuthSuccess;
      expect(success.session.accessToken, isNotNull);
      final newUid = success.user.id;
      expect(backend.currentUserFor(newUid)?.email, 'carol@showcase.app');

      final dup = await backend.signUp(const EmailPasswordCredentials(
        email: 'carol@showcase.app',
        password: 'x',
      ));
      expect(dup, isA<AuthFailure>());
      expect(
        (dup as AuthFailure).reason,
        AuthFailureReason.emailAlreadyInUse,
      );

      await backend.signOut();
      final signIn = await backend.signIn(const EmailPasswordCredentials(
        email: 'carol@showcase.app',
        password: 'pw-carol',
      ));
      expect(signIn, isA<AuthSuccess>());
    });

    test('token refresh rotates: old token dies, bogus token fails', () async {
      final backend = SeedAuthBackend();
      final auth = await backend.signIn(const EmailPasswordCredentials(
        email: 'bob@showcase.app',
        password: 'seed-bob',
      )) as AuthSuccess;
      final token = auth.session.accessToken!;

      final refreshed = await backend.refreshToken(token);
      expect(refreshed, isA<AuthSuccess>());
      final rotated = (refreshed as AuthSuccess).session.accessToken!;
      expect(rotated, isNot(token));

      final oldDead = await backend.refreshToken(token);
      expect(oldDead, isA<AuthFailure>());
      expect((oldDead as AuthFailure).reason, AuthFailureReason.tokenExpired);

      final bogus = await backend.refreshToken('bogus');
      expect(bogus, isA<AuthFailure>());
      expect((bogus as AuthFailure).reason, AuthFailureReason.tokenExpired);
    });

    test('tokens mint monotonically (tok_1, tok_2, …)', () async {
      final backend = SeedAuthBackend();
      final a = await backend.signIn(const EmailPasswordCredentials(
        email: 'alice@showcase.app',
        password: 'seed-alice',
      )) as AuthSuccess;
      final b = await backend.signIn(const EmailPasswordCredentials(
        email: 'bob@showcase.app',
        password: 'seed-bob',
      )) as AuthSuccess;
      expect(a.session.accessToken, 'tok_1');
      expect(b.session.accessToken, 'tok_2');
    });

    test('sign-up uids mint monotonically (user_1, user_2, …)', () async {
      final backend = SeedAuthBackend();
      final a = await backend.signUp(const EmailPasswordCredentials(
        email: 'a@showcase.app',
        password: 'pw',
      )) as AuthSuccess;
      final b = await backend.signUp(const EmailPasswordCredentials(
        email: 'b@showcase.app',
        password: 'pw',
      )) as AuthSuccess;
      expect(a.user.id, 'user_1');
      expect(b.user.id, 'user_2');
    });

    test('Apple/Google sign-in resolve deterministic demo identities', () async {
      final backend = SeedAuthBackend();
      final apple = await backend.signInWithApple();
      expect(apple, isA<AuthSuccess>());
      expect((apple as AuthSuccess).user.id, 'apple_demo_user');
      expect(apple.user.email, 'relay@apple.example');
      expect(apple.user.metadata['provider'], 'apple');

      final google = await backend.signInWithGoogle();
      expect(google, isA<AuthSuccess>());
      expect((google as AuthSuccess).user.id, 'google_demo_user');
      expect(google.user.email, 'demo@google.example');
      expect(google.user.metadata['provider'], 'google');

      // Repeat sign-in resolves the same identity.
      final again = await backend.signInWithApple() as AuthSuccess;
      expect(again.user.id, 'apple_demo_user');
    });

    test('authStateChanges replays current user then live changes', () async {
      final backend = SeedAuthBackend();
      final emitted = <AuthUser?>[];
      final sub = backend.authStateChanges.listen(emitted.add);
      // Let the async* replay land and the generator subscribe to the live
      // controller before mutating (broadcast streams do not buffer).
      await Future<void>.delayed(Duration.zero);
      await backend.signIn(const EmailPasswordCredentials(
        email: 'alice@showcase.app',
        password: 'seed-alice',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(2));
      expect(emitted[0], isNull); // replayed signed-out state
      expect(emitted[1]?.id, 'seed_alice');
      await sub.cancel();
    });

    test('use after dispose throws StateError', () async {
      final backend = SeedAuthBackend();
      await backend.dispose();
      expect(
        () => backend.signIn(const EmailPasswordCredentials(
          email: 'alice@showcase.app',
          password: 'seed-alice',
        )),
        throwsStateError,
      );
    });
  });
}
