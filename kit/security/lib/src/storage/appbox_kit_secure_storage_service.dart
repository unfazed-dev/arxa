/// Port for encrypted, OS-backed key-value storage.
///
/// String-keyed, String-valued. The production binding
/// (`FlutterSecureStorageAppBoxKitSecureStorageService`) wraps `flutter_secure_storage`
/// (iOS Keychain / Android Keystore-backed EncryptedSharedPreferences); the
/// scriptable fake lives in `package:appbox_kit_security/appbox_kit_testing.dart`.
///
/// This is where secrets at rest live — an app-held crypto key, a hashed PIN,
/// a session token. Values are opaque to the port; use [AppBoxKitCryptoService] to
/// encrypt structured payloads before writing them here if you need more than
/// the platform's own at-rest encryption.
abstract interface class AppBoxKitSecureStorageService {
  /// Reads the value for [key], or `null` if absent.
  Future<String?> read(String key);

  /// Writes [value] under [key], replacing any existing value.
  Future<void> write(String key, String value);

  /// Deletes [key] if present (a no-op otherwise).
  Future<void> delete(String key);

  /// Whether a value is stored for [key].
  Future<bool> containsKey(String key);

  /// Removes every value this service owns.
  Future<void> deleteAll();
}
