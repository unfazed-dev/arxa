/// appbox_kit_security — a plugin-neutral security capability kit.
///
/// Four independent ports, each depended on through a seam with plugin-neutral
/// typed results, and a production binding behind it:
///
/// - **Biometrics** — [KitBiometricService] ([availability] /
///   [authenticate] → typed [KitBiometricResult]); production binding
///   `LocalAuthKitBiometricService` over `local_auth`.
/// - **Secure storage** — [KitSecureStorageService] over
///   `flutter_secure_storage`.
/// - **Crypto** — [KitCryptoService] (AES-GCM-256, SHA-256, HMAC) with the
///   pure-Dart `CryptographyKitCryptoService` default; typed [KitCryptoFailure].
/// - **App-lock** — the pure-Dart [KitAppLockController] state machine composing
///   a [KitBiometricService] and a [KitPinVerifier]
///   (`SecureStoragePinVerifier` included).
/// - **Device integrity** — [KitDeviceIntegrityService] → [KitIntegrityReport];
///   ships only the [UnimplementedKitDeviceIntegrityService] stub (phase 2,
///   native-first).
///
/// This package intentionally depends on no other kit (not `appbox_kit`,
/// `stacked`, or `stacked_services`) — it is a pure capability kit. Scriptable
/// fakes live in `package:appbox_kit_security/testing.dart`.
library;

// Biometrics.
export 'src/biometric/kit_biometric_availability.dart';
export 'src/biometric/kit_biometric_result.dart';
export 'src/biometric/kit_biometric_service.dart';
export 'src/biometric/kit_biometric_type.dart';
export 'src/biometric/local_auth_kit_biometric_service.dart';

// Secure storage.
export 'src/storage/flutter_secure_storage_kit_secure_storage_service.dart';
export 'src/storage/kit_secure_storage_service.dart';

// Crypto.
export 'src/crypto/cryptography_kit_crypto_service.dart';
export 'src/crypto/kit_crypto_failure.dart';
export 'src/crypto/kit_crypto_key.dart';
export 'src/crypto/kit_crypto_service.dart';
export 'src/crypto/kit_secret_box.dart';

// App-lock.
export 'src/app_lock/kit_app_lock_config.dart';
export 'src/app_lock/kit_app_lock_controller.dart';
export 'src/app_lock/kit_app_lock_outcome.dart';
export 'src/app_lock/kit_app_lock_state.dart';
export 'src/app_lock/kit_pin_verifier.dart';
export 'src/app_lock/secure_storage_pin_verifier.dart';

// Device integrity.
export 'src/integrity/kit_device_integrity_service.dart';
export 'src/integrity/kit_integrity_report.dart';
export 'src/integrity/kit_tri_state.dart';
export 'src/integrity/unimplemented_kit_device_integrity_service.dart';
