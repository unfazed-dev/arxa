import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'kit_crypto_failure.dart';
import 'kit_crypto_key.dart';
import 'kit_crypto_service.dart';
import 'kit_secret_box.dart';

/// Default pure-Dart [KitCryptoService] over the `cryptography` package.
///
/// AES-GCM-256 with a 12-byte nonce and 16-byte tag; SHA-256 and HMAC-SHA256
/// for hashing. In `flutter test` (no plugin registered) `cryptography` uses
/// its `DartCryptography` fallback, so this backend is fully exercisable off
/// device. The `cryptography` types (`SecretKey`, `SecretBox`, `Mac`) never
/// escape this file — the port speaks bytes and neutral value types.
class CryptographyKitCryptoService implements KitCryptoService {
  CryptographyKitCryptoService();

  final AesGcm _aesGcm = AesGcm.with256bits();
  final Sha256 _sha256 = Sha256();
  final Hmac _hmacSha256 = Hmac.sha256();

  @override
  Future<KitCryptoKey> generateKey() async {
    final secretKey = await _aesGcm.newSecretKey();
    return KitCryptoKey(await secretKey.extractBytes());
  }

  @override
  List<int> generateNonce() => _aesGcm.newNonce();

  @override
  Future<KitSecretBox> encryptBytes(
    List<int> data, {
    required KitCryptoKey key,
    List<int>? nonce,
  }) async {
    final box = await _aesGcm.encrypt(
      data,
      secretKey: SecretKey(key.bytes),
      nonce: nonce ?? _aesGcm.newNonce(),
    );
    return KitSecretBox(
      nonce: box.nonce,
      cipherText: box.cipherText,
      mac: box.mac.bytes,
    );
  }

  @override
  Future<Uint8List> decryptBytes(
    KitSecretBox box, {
    required KitCryptoKey key,
  }) async {
    try {
      final clear = await _aesGcm.decrypt(
        SecretBox(box.cipherText, nonce: box.nonce, mac: Mac(box.mac)),
        secretKey: SecretKey(key.bytes),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError catch (e) {
      throw KitCryptoFailure(
        KitCryptoFailureReason.authentication,
        message: 'Ciphertext failed authentication (wrong key or tampered).',
        cause: e,
      );
    } on ArgumentError catch (e) {
      // e.g. a key or nonce of the wrong length.
      throw KitCryptoFailure(
        KitCryptoFailureReason.malformed,
        message: e.message?.toString(),
        cause: e,
      );
    }
  }

  @override
  Future<KitSecretBox> encryptString(
    String data, {
    required KitCryptoKey key,
    List<int>? nonce,
  }) =>
      encryptBytes(utf8.encode(data), key: key, nonce: nonce);

  @override
  Future<String> decryptString(
    KitSecretBox box, {
    required KitCryptoKey key,
  }) async {
    final clear = await decryptBytes(box, key: key);
    try {
      return utf8.decode(clear);
    } on FormatException catch (e) {
      throw KitCryptoFailure(
        KitCryptoFailureReason.malformed,
        message: 'Decrypted bytes are not valid UTF-8.',
        cause: e,
      );
    }
  }

  @override
  Future<Uint8List> sha256(List<int> data) async {
    final hash = await _sha256.hash(data);
    return Uint8List.fromList(hash.bytes);
  }

  @override
  Future<Uint8List> hmacSha256(
    List<int> data, {
    required KitCryptoKey key,
  }) async {
    final mac = await _hmacSha256.calculateMac(
      data,
      secretKey: SecretKey(key.bytes),
    );
    return Uint8List.fromList(mac.bytes);
  }
}
