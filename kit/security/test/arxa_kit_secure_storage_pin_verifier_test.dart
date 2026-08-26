import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_security/arxa_kit_security.dart';
import 'package:arxa_kit_security/arxa_kit_testing.dart';

/// [SecureStoragePinVerifier] over the real [CryptographyArxaKitCryptoService] +
/// [FakeArxaKitSecureStorageService]. Verifies the documented contract: plaintext
/// never persisted, per-PIN random salt, correct/wrong-PIN discrimination.
void main() {
  late FakeArxaKitSecureStorageService storage;
  late SecureStoragePinVerifier verifier;

  setUp(() {
    storage = FakeArxaKitSecureStorageService();
    verifier = SecureStoragePinVerifier(
      storage: storage,
      crypto: CryptographyArxaKitCryptoService(),
    );
  });

  test('kit.security.pin-verifier — a PIN can be set and only the matching PIN verifies', () async {
    await verifier.setPin('1234');
    expect(await verifier.hasPin(), isTrue);
    expect(await verifier.verifyPin('1234'), isTrue);
    expect(await verifier.verifyPin('0000'), isFalse);
  });

  test('kit.security.pin-verifier — re-setting the same PIN draws a fresh salt', () async {
    await verifier.setPin('1234');
    final firstSnapshot = Map<String, String>.from(storage.snapshot);

    await verifier.setPin('1234');
    final secondSnapshot = storage.snapshot;

    // Same PIN, but the persisted blobs differ → a new random salt was drawn.
    expect(secondSnapshot, isNot(equals(firstSnapshot)));
    // …and the new salt still verifies the correct PIN.
    expect(await verifier.verifyPin('1234'), isTrue);
  });

  test('kit.security.pin-verifier — the plaintext PIN is never stored verbatim', () async {
    await verifier.setPin('secret-pin');
    for (final value in storage.snapshot.values) {
      expect(value.contains('secret-pin'), isFalse,
          reason: 'Plaintext PIN leaked into secure storage: $value');
    }
  });

  test('kit.security.pin-verifier — clearPin removes the stored PIN', () async {
    await verifier.setPin('1234');
    await verifier.clearPin();
    expect(await verifier.hasPin(), isFalse);
    expect(await verifier.verifyPin('1234'), isFalse);
  });
}
