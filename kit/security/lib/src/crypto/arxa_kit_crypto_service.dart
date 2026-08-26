import 'dart:typed_data';

import 'arxa_kit_crypto_failure.dart';
import 'arxa_kit_crypto_key.dart';
import 'arxa_kit_secret_box.dart';

/// Port for authenticated symmetric encryption and hashing.
///
/// The default backend (`CryptographyArxaKitCryptoService`) is pure Dart over the
/// `cryptography` package: AES-GCM-256 for [encryptBytes] / [decryptBytes],
/// SHA-256 for [sha256], HMAC-SHA256 for [hmacSha256]. No backend type leaks
/// through the port — inputs and outputs are plain bytes and the neutral
/// [ArxaKitCryptoKey] / [ArxaKitSecretBox] value types.
///
/// Encryption is authenticated: [decryptBytes] / [decryptString] throw a
/// [ArxaKitCryptoFailure] (rather than returning garbage) when the key is wrong or
/// the ciphertext was tampered with.
abstract interface class ArxaKitCryptoService {
  /// Generates a fresh random key suitable for [encryptBytes] (256-bit).
  Future<ArxaKitCryptoKey> generateKey();

  /// Returns a fresh random nonce of the size [encryptBytes] expects.
  ///
  /// Callers rarely need this — [encryptBytes] generates one when [nonce] is
  /// omitted — but it is exposed for protocols that manage nonces explicitly.
  List<int> generateNonce();

  /// Encrypts [data] under [key], generating a random nonce unless one is
  /// supplied. Reusing a nonce with the same key breaks confidentiality —
  /// prefer letting this generate one.
  Future<ArxaKitSecretBox> encryptBytes(
    List<int> data, {
    required ArxaKitCryptoKey key,
    List<int>? nonce,
  });

  /// Decrypts [box] under [key].
  ///
  /// Throws [ArxaKitCryptoFailure] with [ArxaKitCryptoFailureReason.authentication]
  /// when authentication fails (wrong key or tampering).
  Future<Uint8List> decryptBytes(
    ArxaKitSecretBox box, {
    required ArxaKitCryptoKey key,
  });

  /// UTF-8 encodes [data], then [encryptBytes].
  Future<ArxaKitSecretBox> encryptString(
    String data, {
    required ArxaKitCryptoKey key,
    List<int>? nonce,
  });

  /// [decryptBytes] then UTF-8 decodes. Throws [ArxaKitCryptoFailure] on
  /// authentication failure.
  Future<String> decryptString(
    ArxaKitSecretBox box, {
    required ArxaKitCryptoKey key,
  });

  /// SHA-256 digest of [data].
  Future<Uint8List> sha256(List<int> data);

  /// HMAC-SHA256 of [data] keyed by [key].
  Future<Uint8List> hmacSha256(
    List<int> data, {
    required ArxaKitCryptoKey key,
  });
}
