import 'dart:typed_data';

import 'appbox_kit_crypto_failure.dart';
import 'appbox_kit_crypto_key.dart';
import 'appbox_kit_secret_box.dart';

/// Port for authenticated symmetric encryption and hashing.
///
/// The default backend (`CryptographyAppBoxKitCryptoService`) is pure Dart over the
/// `cryptography` package: AES-GCM-256 for [encryptBytes] / [decryptBytes],
/// SHA-256 for [sha256], HMAC-SHA256 for [hmacSha256]. No backend type leaks
/// through the port — inputs and outputs are plain bytes and the neutral
/// [AppBoxKitCryptoKey] / [AppBoxKitSecretBox] value types.
///
/// Encryption is authenticated: [decryptBytes] / [decryptString] throw a
/// [AppBoxKitCryptoFailure] (rather than returning garbage) when the key is wrong or
/// the ciphertext was tampered with.
abstract interface class AppBoxKitCryptoService {
  /// Generates a fresh random key suitable for [encryptBytes] (256-bit).
  Future<AppBoxKitCryptoKey> generateKey();

  /// Returns a fresh random nonce of the size [encryptBytes] expects.
  ///
  /// Callers rarely need this — [encryptBytes] generates one when [nonce] is
  /// omitted — but it is exposed for protocols that manage nonces explicitly.
  List<int> generateNonce();

  /// Encrypts [data] under [key], generating a random nonce unless one is
  /// supplied. Reusing a nonce with the same key breaks confidentiality —
  /// prefer letting this generate one.
  Future<AppBoxKitSecretBox> encryptBytes(
    List<int> data, {
    required AppBoxKitCryptoKey key,
    List<int>? nonce,
  });

  /// Decrypts [box] under [key].
  ///
  /// Throws [AppBoxKitCryptoFailure] with [AppBoxKitCryptoFailureReason.authentication]
  /// when authentication fails (wrong key or tampering).
  Future<Uint8List> decryptBytes(
    AppBoxKitSecretBox box, {
    required AppBoxKitCryptoKey key,
  });

  /// UTF-8 encodes [data], then [encryptBytes].
  Future<AppBoxKitSecretBox> encryptString(
    String data, {
    required AppBoxKitCryptoKey key,
    List<int>? nonce,
  });

  /// [decryptBytes] then UTF-8 decodes. Throws [AppBoxKitCryptoFailure] on
  /// authentication failure.
  Future<String> decryptString(
    AppBoxKitSecretBox box, {
    required AppBoxKitCryptoKey key,
  });

  /// SHA-256 digest of [data].
  Future<Uint8List> sha256(List<int> data);

  /// HMAC-SHA256 of [data] keyed by [key].
  Future<Uint8List> hmacSha256(
    List<int> data, {
    required AppBoxKitCryptoKey key,
  });
}
