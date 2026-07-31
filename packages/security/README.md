# stacked_kit_security

A **plugin-neutral security capability kit** for `stacked_kit` apps: typed
biometric authentication, encrypted at-rest storage, authenticated symmetric
crypto, a pure-Dart app-lock state machine, and a device-integrity port. Five
independent seams, each depended on through a typed port with plugin-neutral
value types and results — the backing plugins never leak past the boundary.

- **Version:** 0.1.0 · `publish_to: 'none'` · Dart `>=3.0.3 <4.0.0`
- **Depends on:** no other kit (not `stacked_kit`, `stacked`, or
  `stacked_services`). The app wires the ports; scriptable fakes live in
  `package:stacked_kit_security/testing.dart`.

## Scope

- **Biometrics** — `KitBiometricService`: `availability()` (unsupported /
  notEnrolled / available + the enrolled modalities) and `authenticate()` →
  typed `KitBiometricResult` (`KitBiometricSuccess` /
  `KitBiometricFailure` with a reason enum: cancelled, lockedOut,
  permanentlyLockedOut, notEnrolled, unavailable, error). Production binding
  `LocalAuthKitBiometricService` maps `local_auth`'s `BiometricType` and
  `LocalAuthExceptionCode` onto the kit's typed values.
- **Secure storage** — `KitSecureStorageService` (read / write / delete /
  containsKey / deleteAll, String-keyed) backed by `flutter_secure_storage`
  (iOS Keychain / Android EncryptedSharedPreferences + Keystore).
- **Crypto** — `KitCryptoService`: AES-GCM-256 encrypt/decrypt, SHA-256, and
  HMAC-SHA256. `decryptBytes` throws a typed `KitCryptoFailure` whose
  `authentication` reason is the security-critical tamper / wrong-key signal
  — the plaintext is never handed back on a failed tag. Default pure-Dart
  backend `CryptographyKitCryptoService` over the `cryptography` package; its
  `cryptography` types (`SecretKey`, `SecretBox`, `Mac`) stay behind the seam.
- **App-lock** — the pure-Dart `KitAppLockController` state machine
  (unlocked / locked / unlocking) composing a `KitBiometricService` and a
  `KitPinVerifier`. `maxAttempts` biometric failures (or a platform permanent
  lockout) lock out the biometric path and force PIN fallback; `maxAttempts`
  PIN failures start a cooldown window; any success resets every counter.
  Lifecycle is pushed in by the host (`didEnterBackground` /
  `didEnterForeground`); the clock is injectable. `SecureStoragePinVerifier`
  (salted HMAC, constant-time compare) ships as the portable PIN backend.
- **Device integrity** — `KitDeviceIntegrityService` → `KitIntegrityReport`
  (jailbroken/rooted, developerMode, emulator, debuggable, each a
  first-class `KitTriState` so a partial platform never reports a false
  "no"). Ships **only** the `UnimplementedKitDeviceIntegrityService` stub;
  the scriptable fake drives UIs and tests.

## Security notes (read before relying on this kit)

- **AES-GCM nonce handling.** `encryptBytes` draws a fresh random 12-byte
  nonce per call unless one is passed in. Never reuse a nonce with the same
  key — a fresh nonce per encryption is the requirement this default
  satisfies. If you supply an explicit nonce, you own uniqueness.
- **PIN storage is HMAC, not a slow KDF.** `SecureStoragePinVerifier` stores a
  per-PIN salted `HMAC-SHA256`. HMAC-SHA256 is fast, so this is **not**
  brute-force-resistant: an attacker who exfiltrates the secure-storage
  contents can grind a short numeric PIN offline. This is the documented
  portable default, acceptable when the app enforces attempt limits — which
  `KitAppLockController` does (biometric lockout + PIN cooldown). For a
  high-value lock, back the PIN with a rate-limited secure element
  (StrongBox / Secure Enclave) or a slow KDF (Argon2/ PBKDF2) by supplying
  your own `KitPinVerifier`.
- **Biometric-only.** `LocalAuthKitBiometricService` passes `biometricOnly:
  true`; the device passcode fallback is the app-lock's job, not the
  biometric seam's.
- **Device integrity is phase 2.** No production binding ships; the stub
  throws. A real check must be native-first (no root-detection plugin
  dependency is added by this kit).

## Dependency direction

This package depends on no other kit. The host app (or `stacked_kit` core)
binds the ports in its locator:

```dart
// app bootstrap — choose the production bindings you need
locator.registerSingleton<KitBiometricService>(LocalAuthKitBiometricService());
locator.registerSingleton<KitSecureStorageService>(
  FlutterSecureStorageKitSecureStorageService(),
);
locator.registerSingleton<KitCryptoService>(CryptographyKitCryptoService());
```

## Backing packages (verified pub.dev 2026-07-14)

- `local_auth: ^3.0.2` — biometric auth (publisher `flutter.dev`).
- `flutter_secure_storage: ^10.3.1` — Keychain / Keystore-backed storage.
- `cryptography: ^2.9.0` — pure-Dart AES-GCM / SHA-256 / HMAC (uses the
  package's `DartCryptography` fallback in `flutter test`, so the crypto
  backend is fully exercisable off-device).

## Phase notes

- **Implemented now:** biometrics, secure storage, crypto, app-lock.
- **Stubbed (native-first, later phase):** device integrity
  (`UnimplementedKitDeviceIntegrityService` throws; wire
  `FakeKitDeviceIntegrityService` for UIs/tests).
