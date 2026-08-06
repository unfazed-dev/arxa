/// appbox_kit_security — a plugin-neutral security capability kit.
///
/// Four independent ports, each depended on through a seam with plugin-neutral
/// typed results, and a production binding behind it:
///
/// - **Biometrics** — [AppBoxKitBiometricService] ([availability] /
///   [authenticate] → typed [AppBoxKitBiometricResult]); production binding
///   `LocalAuthAppBoxKitBiometricService` over `local_auth`.
/// - **Secure storage** — [AppBoxKitSecureStorageService] over
///   `flutter_secure_storage`.
/// - **Crypto** — [AppBoxKitCryptoService] (AES-GCM-256, SHA-256, HMAC) with the
///   pure-Dart `CryptographyAppBoxKitCryptoService` default; typed [AppBoxKitCryptoFailure].
/// - **App-lock** — the pure-Dart [AppBoxKitAppLockController] state machine composing
///   a [AppBoxKitBiometricService] and a [AppBoxKitPinVerifier]
///   (`SecureStoragePinVerifier` included).
/// - **Device integrity** — [AppBoxKitDeviceIntegrityService] → [AppBoxKitIntegrityReport];
///   ships only the [UnimplementedAppBoxKitDeviceIntegrityService] stub (phase 2,
///   native-first).
///
/// This package intentionally depends on no other kit (not `appbox_kit`,
/// `stacked`, or `stacked_services`) — it is a pure capability kit. Scriptable
/// fakes live in `package:appbox_kit_security/appbox_kit_testing.dart`.
library;

// Biometrics.
export 'src/biometric/appbox_kit_biometric_availability.dart';
export 'src/biometric/appbox_kit_biometric_result.dart';
export 'src/biometric/appbox_kit_biometric_service.dart';
export 'src/biometric/appbox_kit_biometric_type.dart';
export 'src/biometric/appbox_kit_local_auth_biometric_service.dart';

// Secure storage.
export 'src/storage/appbox_kit_flutter_secure_storage_secure_storage_service.dart';
export 'src/storage/appbox_kit_secure_storage_service.dart';

// Crypto.
export 'src/crypto/appbox_kit_cryptography_crypto_service.dart';
export 'src/crypto/appbox_kit_crypto_failure.dart';
export 'src/crypto/appbox_kit_crypto_key.dart';
export 'src/crypto/appbox_kit_crypto_service.dart';
export 'src/crypto/appbox_kit_secret_box.dart';

// App-lock.
export 'src/app_lock/appbox_kit_app_lock_config.dart';
export 'src/app_lock/appbox_kit_app_lock_controller.dart';
export 'src/app_lock/appbox_kit_app_lock_outcome.dart';
export 'src/app_lock/appbox_kit_app_lock_state.dart';
export 'src/app_lock/appbox_kit_pin_verifier.dart';
export 'src/app_lock/appbox_kit_secure_storage_pin_verifier.dart';

// Device integrity.
export 'src/integrity/appbox_kit_device_integrity_service.dart';
export 'src/integrity/appbox_kit_integrity_report.dart';
export 'src/integrity/appbox_kit_tri_state.dart';
export 'src/integrity/appbox_kit_unimplemented_device_integrity_service.dart';
