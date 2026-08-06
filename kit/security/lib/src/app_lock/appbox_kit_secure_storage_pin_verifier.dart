import 'dart:convert';

import '../crypto/appbox_kit_crypto_key.dart';
import '../crypto/appbox_kit_crypto_service.dart';
import '../storage/appbox_kit_secure_storage_service.dart';
import 'appbox_kit_pin_verifier.dart';

/// A [AppBoxKitPinVerifier] that stores a per-PIN-salted HMAC of the PIN in
/// [AppBoxKitSecureStorageService], hashing via [AppBoxKitCryptoService].
///
/// The plaintext PIN is never persisted: [setPin] draws a random salt, computes
/// `HMAC-SHA256(pin, key: salt)`, and stores the salt and digest (base64).
/// [verifyPin] recomputes and compares in constant time.
///
/// Security note: HMAC-SHA256 is fast, so this is *not* a brute-force-resistant
/// KDF. An attacker who exfiltrates the storage contents can grind a short
/// numeric PIN offline. For high-value locks, back the PIN with a rate-limited
/// secure element (StrongBox / Secure Enclave) or a slow KDF; this verifier is
/// the portable default.
class SecureStoragePinVerifier implements AppBoxKitPinVerifier {
  SecureStoragePinVerifier({
    required AppBoxKitSecureStorageService storage,
    required AppBoxKitCryptoService crypto,
    String keyPrefix = 'appbox_kit_security.app_lock',
  })  : _storage = storage,
        _crypto = crypto,
        _saltKey = '$keyPrefix.pin_salt',
        _digestKey = '$keyPrefix.pin_digest';

  final AppBoxKitSecureStorageService _storage;
  final AppBoxKitCryptoService _crypto;
  final String _saltKey;
  final String _digestKey;

  @override
  Future<bool> hasPin() => _storage.containsKey(_digestKey);

  @override
  Future<void> setPin(String pin) async {
    final salt = _crypto.generateNonce();
    final digest = await _crypto.hmacSha256(
      utf8.encode(pin),
      key: AppBoxKitCryptoKey(salt),
    );
    await _storage.write(_saltKey, base64Encode(salt));
    await _storage.write(_digestKey, base64Encode(digest));
  }

  @override
  Future<bool> verifyPin(String pin) async {
    final saltB64 = await _storage.read(_saltKey);
    final digestB64 = await _storage.read(_digestKey);
    if (saltB64 == null || digestB64 == null) return false;

    final expected = base64Decode(digestB64);
    final actual = await _crypto.hmacSha256(
      utf8.encode(pin),
      key: AppBoxKitCryptoKey(base64Decode(saltB64)),
    );
    return _constantTimeEquals(actual, expected);
  }

  @override
  Future<void> clearPin() async {
    await _storage.delete(_saltKey);
    await _storage.delete(_digestKey);
  }

  /// Length-checked, timing-safe byte comparison.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
