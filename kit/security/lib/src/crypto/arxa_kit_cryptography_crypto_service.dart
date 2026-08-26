import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'arxa_kit_crypto_failure.dart';
import 'arxa_kit_crypto_key.dart';
import 'arxa_kit_crypto_service.dart';
import 'arxa_kit_secret_box.dart';

/// Default pure-Dart [ArxaKitCryptoService] over the `cryptography` package.
///
/// AES-GCM-256 with a 12-byte nonce and 16-byte tag; SHA-256 and HMAC-SHA256
/// for hashing. In `flutter test` (no plugin registered) `cryptography` uses
/// its `DartCryptography` fallback, so this backend is fully exercisable off
/// device. The `cryptography` types (`SecretKey`, `SecretBox`, `Mac`) never
/// escape this file — the port speaks bytes and neutral value types.
class CryptographyArxaKitCryptoService implements ArxaKitCryptoService {
  CryptographyArxaKitCryptoService();

  final AesGcm _aesGcm = AesGcm.with256bits();
  final Sha256 _sha256 = Sha256();
  final Hmac _hmacSha256 = Hmac.sha256();

  @override
  Future<ArxaKitCryptoKey> generateKey() async {
    final secretKey = await _aesGcm.newSecretKey();
    return ArxaKitCryptoKey(await secretKey.extractBytes());
  }

  @override
  List<int> generateNonce() => _aesGcm.newNonce();

  @override
  Future<ArxaKitSecretBox> encryptBytes(
    List<int> data, {
    required ArxaKitCryptoKey key,
    List<int>? nonce,
  }) async {
    final box = await _aesGcm.encrypt(
      data,
      secretKey: SecretKey(key.bytes),
      nonce: nonce ?? _aesGcm.newNonce(),
    );
    return ArxaKitSecretBox(
      nonce: box.nonce,
      cipherText: box.cipherText,
      mac: box.mac.bytes,
    );
  }

  @override
  Future<Uint8List> decryptBytes(
    ArxaKitSecretBox box, {
    required ArxaKitCryptoKey key,
  }) async {
    try {
      final clear = await _aesGcm.decrypt(
        SecretBox(box.cipherText, nonce: box.nonce, mac: Mac(box.mac)),
        secretKey: SecretKey(key.bytes),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError catch (e) {
      throw ArxaKitCryptoFailure(
        ArxaKitCryptoFailureReason.authentication,
        message: 'Ciphertext failed authentication (wrong key or tampered).',
        cause: e,
      );
    } on ArgumentError catch (e) {
      // e.g. a key or nonce of the wrong length.
      throw ArxaKitCryptoFailure(
        ArxaKitCryptoFailureReason.malformed,
        message: e.message?.toString(),
        cause: e,
      );
    }
  }

  @override
  Future<ArxaKitSecretBox> encryptString(
    String data, {
    required ArxaKitCryptoKey key,
    List<int>? nonce,
  }) =>
      encryptBytes(utf8.encode(data), key: key, nonce: nonce);

  @override
  Future<String> decryptString(
    ArxaKitSecretBox box, {
    required ArxaKitCryptoKey key,
  }) async {
    final clear = await decryptBytes(box, key: key);
    try {
      return utf8.decode(clear);
    } on FormatException catch (e) {
      throw ArxaKitCryptoFailure(
        ArxaKitCryptoFailureReason.malformed,
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
    required ArxaKitCryptoKey key,
  }) async {
    final mac = await _hmacSha256.calculateMac(
      data,
      secretKey: SecretKey(key.bytes),
    );
    return Uint8List.fromList(mac.bytes);
  }
}
