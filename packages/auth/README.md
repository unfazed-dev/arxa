# stacked_kit_auth

An **API-first** identity seam for `stacked_kit` apps. One port
(`KitAuthService`), a typed `AuthResult`, and an in-memory default backend
that's real enough to build the whole auth UI against before any real backend
lands.

- **Version:** 0.1.0 · `publish_to: 'none'` · Dart `>=3.0.3 <4.0.0`
- **Depends on:** the Flutter SDK only. **No** dependency on `stacked_kit`,
  `stacked`, `stacked_services`, or any app code.

> Naming note: `stacked_kit_data` also ships a `KitAuthService` (a
> backend-identity-coupled variant with `session$`/`currentSession`). This
> package is the standalone, API-first seam (`authStateChanges`/`currentUser`,
> sealed `AuthResult`). The two are independent today; if a workspace ever
> imports both, one must be namespaced. That reconciliation is a downstream
> (workspace-wiring) decision, not this package's.
>
> Workspace reconciliation (Task #7) verified zero co-imports across the repo:
> no file imports both this package and `stacked_kit_data`'s auth. **Planned
> resolution: Phase 4 folds `stacked_kit_data/lib/auth/` (seed/appwrite/
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

**Stubs (`UnimplementedError` + TODO):**
- `SeedAuthBackend` (**phase-4**) — the seam onto the app's existing Seed auth
  service. Kept a clean interface seam: it will NOT import app code; the host
  injects the operations it needs.
- `AppleSignInProvider` / `GoogleSignInProvider` (**phase-later**) — native
  OAuth via `sign_in_with_apple ^8.1.0` / `google_sign_in ^7.2.0`.

**Non-goals:** real credential storage/hashing, session persistence, RBAC,
account recovery. The default backend is a build-time convenience, not a
security boundary.

## Usage

```dart
import 'package:stacked_kit_auth/stacked_kit_auth.dart';

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
import 'package:stacked_kit_auth/testing.dart';

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

1. **Now:** port + in-memory default + fakes (this package).
2. **Phase-later:** native OAuth providers (Apple / Google).
3. **Phase-4:** `SeedAuthBackend` wired to the app's Seed auth service.

Workspace wiring (path deps, locator registration, the `KitAuthService`
name reconciliation with `stacked_kit_data`) is a downstream pass.
