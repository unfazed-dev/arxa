/// Abstract PIN store the app supplies to [ArxaKitAppLockController].
///
/// The kit ships `SecureStoragePinVerifier` (a salted-HMAC verifier over
/// [ArxaKitSecureStorageService] + [ArxaKitCryptoService]); apps with a different PIN
/// backend (a server check, an existing keychain layout) implement this
/// directly. [verifyPin] is a predicate — a match/no-match query — not an
/// operation outcome, so it returns a bool by design.
abstract interface class ArxaKitPinVerifier {
  /// Whether a PIN has been set.
  Future<bool> hasPin();

  /// Sets (or replaces) the stored PIN.
  Future<void> setPin(String pin);

  /// Whether [pin] matches the stored PIN.
  Future<bool> verifyPin(String pin);

  /// Removes the stored PIN.
  Future<void> clearPin();
}
