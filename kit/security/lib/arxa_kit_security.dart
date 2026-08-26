/// arxa_kit_security — a plugin-neutral security capability kit.
///
/// Four independent ports, each depended on through a seam with plugin-neutral
/// typed results, and a production binding behind it:
///
/// - **Biometrics** — [ArxaKitBiometricService] ([availability] /
///   [authenticate] → typed [ArxaKitBiometricResult]); production binding
///   `LocalAuthArxaKitBiometricService` over `local_auth`.
/// - **Secure storage** — [ArxaKitSecureStorageService] over
///   `flutter_secure_storage`.
/// - **Crypto** — [ArxaKitCryptoService] (AES-GCM-256, SHA-256, HMAC) with the
///   pure-Dart `CryptographyArxaKitCryptoService` default; typed [ArxaKitCryptoFailure].
/// - **App-lock** — the pure-Dart [ArxaKitAppLockController] state machine composing
///   a [ArxaKitBiometricService] and a [ArxaKitPinVerifier]
///   (`SecureStoragePinVerifier` included).
/// - **Device integrity** — [ArxaKitDeviceIntegrityService] → [ArxaKitIntegrityReport];
///   ships only the [UnimplementedArxaKitDeviceIntegrityService] stub (phase 2,
///   native-first).
///
/// This package intentionally depends on no other kit (not `arxa_kit`,
/// `stacked`, or `stacked_services`) — it is a pure capability kit. Scriptable
/// fakes live in `package:arxa_kit_security/arxa_kit_testing.dart`.
library;

// Biometrics.
export 'src/biometric/arxa_kit_biometric_availability.dart';
export 'src/biometric/arxa_kit_biometric_result.dart';
export 'src/biometric/arxa_kit_biometric_service.dart';
export 'src/biometric/arxa_kit_biometric_type.dart';
export 'src/biometric/arxa_kit_local_auth_biometric_service.dart';

// Secure storage.
export 'src/storage/arxa_kit_flutter_secure_storage_secure_storage_service.dart';
export 'src/storage/arxa_kit_secure_storage_service.dart';

// Crypto.
export 'src/crypto/arxa_kit_cryptography_crypto_service.dart';
export 'src/crypto/arxa_kit_crypto_failure.dart';
export 'src/crypto/arxa_kit_crypto_key.dart';
export 'src/crypto/arxa_kit_crypto_service.dart';
export 'src/crypto/arxa_kit_secret_box.dart';

// App-lock.
export 'src/app_lock/arxa_kit_app_lock_config.dart';
export 'src/app_lock/arxa_kit_app_lock_controller.dart';
export 'src/app_lock/arxa_kit_app_lock_outcome.dart';
export 'src/app_lock/arxa_kit_app_lock_state.dart';
export 'src/app_lock/arxa_kit_pin_verifier.dart';
export 'src/app_lock/arxa_kit_secure_storage_pin_verifier.dart';

// Device integrity.
export 'src/integrity/arxa_kit_device_integrity_service.dart';
export 'src/integrity/arxa_kit_integrity_report.dart';
export 'src/integrity/arxa_kit_tri_state.dart';
export 'src/integrity/arxa_kit_unimplemented_device_integrity_service.dart';
