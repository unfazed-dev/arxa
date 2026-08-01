# appbox_kit_auth

An **API-first** identity seam for `appbox_kit` apps. One port
(`KitAuthService`), a typed `AuthResult`, and an in-memory default backend
that's real enough to build the whole auth UI against before any real backend
lands.

- **Version:** 0.1.0 · `publish_to: 'none'` · Dart `>=3.0.3 <4.0.0`
- **Depends on:** the Flutter SDK, `crypto`, `sign_in_with_apple`, and
  `google_sign_in` (v7 API). **No** dependency on `appbox_kit`, `stacked`,
  `stacked_services`, or any app code.

> Naming note: `appbox_kit_data` also ships a `KitAuthService` (a
> backend-identity-coupled variant with `session$`/`currentSession`). This
> package is the standalone, API-first seam (`authStateChanges`/`currentUser`,
> sealed `AuthResult`). The two are independent today; if a workspace ever
> imports both, one must be namespaced. That reconciliation is a downstream
> (workspace-wiring) decision, not this package's.
>
> Workspace reconciliation (Task #7) verified zero co-imports across the repo:
> no file imports both this package and `appbox_kit_data`'s auth. **Planned
> resolution: Phase 4 folds `appbox_kit_data/lib/auth/` (seed/appwrite/
> supabase backends) into this package behind the API-first seam**, retiring
> the duplicate names. Until then, prefix-import (`as`) if you must touch both.

## Scope

**In (implemented):**
- `KitAuthService` port — `authStateChanges` stream, `currentUser`, `signUp`,
  `signIn`, `signInWithApple`, `signInWithGoogle`, `signOut`, `dispose`.
- Typed models — `AuthUser`, `AuthSession` (with `expiresAt`),
  `EmailPasswordCredentials`, sealed `AuthResult` (`AuthSuccess` /
  `AuthFailure`) with a normalised `AuthFailureReason`.
- `InMemoryKitAuthService` — the default local backend (real password checks,
  deterministic ids, optional session TTL). **Not secure — never production.**
- Scriptable fake (`testing.dart`), including token-expiry.

**Implemented backends:**
- `SeedAuthBackend` — deterministic seeded accounts
  (`alice@showcase.app`/`seed-alice`, `bob@showcase.app`/`seed-bob`), a
  faithful port of the `appboxd/lib/tier1.dart` spec: exact-email matching,
  monotonic uids (`user_1`, …) and tokens (`tok_1`, …), and a public
  `refreshToken` that rotates tokens (old token dies ⇒ `tokenExpired`).
- `AppleSignInProvider` / `GoogleSignInProvider` — native OAuth via
  `sign_in_with_apple ^8.1.0` / `google_sign_in ^7.2.0` (the v7 API:
  `instance` + `initialize` + `authenticate`). Cancellation maps to
  `AuthFailureReason.cancelled`; the JWT (`identityToken` / `idToken`) rides
  on `AuthSession.accessToken` for backend verification. Platform/client-id
  setup is documented in each provider's doc comment.

**Non-goals:** real credential storage/hashing, session persistence, RBAC,
account recovery. The default backend is a build-time convenience, not a
security boundary.

## Usage

```dart
import 'package:appbox_kit_auth/appbox_kit_auth.dart';

final auth = InMemoryKitAuthService();

auth.authStateChanges.listen((user) {
  // null = signed out (also how token-expiry surfaces).
});

final result = await auth.signIn(
  const EmailPasswordCredentials(email: 'a@b.com', password: 'hunter2'),
);
switch (result) {
  case AuthSuccess(:final user):    // signed in
  case AuthFailure(:final reason):  // branch on reason (userNotFound, …)
}
```

## Testing

```dart
import 'package:appbox_kit_auth/testing.dart';

final auth = FakeKitAuthService(
  scriptedResults: [
    AuthSuccess(AuthSession(user: AuthUser(id: 'u1', email: 'a@b.com'))),
    const AuthFailure(AuthFailureReason.tokenExpired),
  ],
);

// Drive token-expiry directly:
auth.expireSession();               // emits signed-out on authStateChanges
```

Factories: `FakeKitAuthService.signedIn(user)`, `.signedOut()`,
`.alwaysFails(reason)`. `FakeKitAuthService.expiredSession(user)` builds an
already-expired `AuthSession` for `AuthSession.isExpiredAt` assertions.

## Phases

1. **Done:** port + in-memory default + fakes; `SeedAuthBackend` (tier1
   port); native Apple/Google OAuth providers.
2. **Phase-4 (remaining):** fold `appbox_kit_data/lib/auth/` (seed/appwrite/
   supabase backends) into this package behind the API-first seam, retiring
   the duplicate `KitAuthService` name.

Workspace wiring (path deps, locator registration, the `KitAuthService`
name reconciliation with `appbox_kit_data`) is a downstream pass.
