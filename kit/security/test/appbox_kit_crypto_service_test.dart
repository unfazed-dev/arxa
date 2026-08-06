import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_security/appbox_kit_security.dart';

/// Exercises the *real* [CryptographyAppBoxKitCryptoService]. The `cryptography`
/// package falls back to its pure-Dart implementation under `flutter test`
/// (no platform channel), so these are genuine AES-GCM-256 / SHA-256 / HMAC
/// round-trips — not fake arithmetic.
void main() {
  const plainText = 'appbox_kit_security round-trip ✅';
  late AppBoxKitCryptoService crypto;
  late AppBoxKitCryptoKey key;

  setUp(() async {
    crypto = CryptographyAppBoxKitCryptoService();
    key = await crypto.generateKey();
  });

  group('encrypt / decrypt round-trip', () {
    test('kit.security.crypto — bytes encrypt then decrypt back to the original', () async {
      const data = <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 255, 128, 64];
      final box = await crypto.encryptBytes(data, key: key);
      final clear = await crypto.decryptBytes(box, key: key);
      expect(listEquals(clear, data), isTrue);
    });

    test('kit.security.crypto — string encrypt then decrypt back to the original', () async {
      final box = await crypto.encryptString(plainText, key: key);
      expect(await crypto.decryptString(box, key: key), plainText);
    });

    test('kit.security.crypto — a fresh random nonce is generated for every encryption', () async {
      final boxA = await crypto.encryptString(plainText, key: key);
      final boxB = await crypto.encryptString(plainText, key: key);
      // Same plaintext + same key, yet the nonce must differ (no nonce reuse).
      expect(listEquals(boxA.nonce, boxB.nonce), isFalse);
      expect(listEquals(boxA.cipherText, boxB.cipherText), isFalse);
      // And both still decrypt cleanly.
      expect(await crypto.decryptString(boxA, key: key), plainText);
      expect(await crypto.decryptString(boxB, key: key), plainText);
    });

    test('kit.security.crypto — an explicit nonce is honoured when supplied', () async {
      const nonce = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
      final box = await crypto.encryptString(plainText, key: key, nonce: nonce);
      expect(box.nonce, nonce);
      expect(await crypto.decryptString(box, key: key), plainText);
    });
  });

  group('tamper / wrong-key detection (authenticated encryption)', () {
    test('kit.security.crypto — flipping a ciphertext byte fails authentication', () async {
      final box = await crypto.encryptString(plainText, key: key);
      final tampered = List<int>.from(box.cipherText);
      tampered[0] ^= 0x01;
      final bad = AppBoxKitSecretBox(
        nonce: box.nonce,
        cipherText: tampered,
        mac: box.mac,
      );
      await expectLater(
        crypto.decryptBytes(bad, key: key),
        throwsA(isA<AppBoxKitCryptoFailure>()),
      );
    });

    test('kit.security.crypto — flipping a MAC byte fails authentication', () async {
      final box = await crypto.encryptString(plainText, key: key);
      final tampered = List<int>.from(box.mac);
      tampered[0] ^= 0x01;
      final bad = AppBoxKitSecretBox(
        nonce: box.nonce,
        cipherText: box.cipherText,
        mac: tampered,
      );
      await expectLater(
        crypto.decryptBytes(bad, key: key),
        throwsA(
          isA<AppBoxKitCryptoFailure>().having(
            (f) => f.reason,
            'reason',
            AppBoxKitCryptoFailureReason.authentication,
          ),
        ),
      );
    });

    test('kit.security.crypto — decrypting with the wrong key fails authentication', () async {
      final box = await crypto.encryptString(plainText, key: key);
      final other = await crypto.generateKey();
      await expectLater(
        crypto.decryptBytes(box, key: other),
        throwsA(
          isA<AppBoxKitCryptoFailure>().having(
            (f) => f.reason,
            'reason',
            AppBoxKitCryptoFailureReason.authentication,
          ),
        ),
      );
    });
  });

  group('concatenated box', () {
    test('kit.security.crypto — round-trips through nonce || cipherText || mac', () async {
      final box = await crypto.encryptString(plainText, key: key);
      final rejoined = AppBoxKitSecretBox.fromConcatenated(box.concatenated);
      expect(rejoined, box);
      expect(await crypto.decryptString(rejoined, key: key), plainText);
    });

    test('kit.security.crypto — rejects a too-short buffer as malformed', () async {
      await expectLater(
        () => AppBoxKitSecretBox.fromConcatenated(<int>[0, 1, 2]),
        throwsA(
          isA<AppBoxKitCryptoFailure>().having(
            (f) => f.reason,
            'reason',
            AppBoxKitCryptoFailureReason.malformed,
          ),
        ),
      );
    });
  });

  group('hashing', () {
    test('kit.security.crypto — SHA-256 is 32 bytes and deterministic', () async {
      final a = await crypto.sha256(plainText.codeUnits);
      final b = await crypto.sha256(plainText.codeUnits);
      expect(a.length, 32);
      expect(listEquals(a, b), isTrue);
      final c = await crypto.sha256('$plainText!'.codeUnits);
      expect(listEquals(a, c), isFalse);
    });

    test('kit.security.crypto — HMAC-SHA256 is 32 bytes', () async {
      final mac = await crypto.hmacSha256(plainText.codeUnits, key: key);
      expect(mac.length, 32);
    });
  });
}
