import 'dart:io';
import 'dart:typed_data';

import 'package:arxa/crypto_aead.dart';
import 'package:arxa/secure_store.dart';
import 'package:arxa/vault.dart';
import 'package:test/test.dart';

/// Vault that always throws — stands in for "no backend on this platform".
class BrokenVault implements Vault {
  @override
  Future<String?> read(String key) => throw UnsupportedError('no backend');
  @override
  Future<void> write(String key, String value) =>
      throw UnsupportedError('no backend');
  @override
  Future<void> delete(String key) => throw UnsupportedError('no backend');
  @override
  Future<List<String>> readAllKeys() => throw UnsupportedError('no backend');
}

void main() {
  late Directory tmp;
  String filePath(String name) => '${tmp.path}/$name';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('secure_store_test');
  });
  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  final payload =
      Uint8List.fromList('{"key":"sk-secret","tier":"paid"}'.codeUnits);

  group('with an OS vault', () {
    test('seal → open round-trips through an InMemoryVault', () async {
      final store = SecureStore(vault: InMemoryVault(), env: const {});
      await store.seal(filePath('state.bin'), payload);
      expect(await store.open(filePath('state.bin')), payload);
    });

    test('generates a 32-byte hex data key in the vault on first use',
        () async {
      final vault = InMemoryVault();
      final store = SecureStore(vault: vault, env: const {});
      await store.seal(filePath('state.bin'), payload);
      final stored = await vault.read(SecureStore.vaultKeyName);
      expect(stored, isNotNull);
      expect(hexDecode(stored!).length, 32);
    });

    test('a second store instance opens the file with the same vault key',
        () async {
      final vault = InMemoryVault();
      await SecureStore(vault: vault, env: const {})
          .seal(filePath('state.bin'), payload);
      final reader = SecureStore(vault: vault, env: const {});
      expect(await reader.open(filePath('state.bin')), payload);
    });

    test('envelope layout: ABX1 magic | 24-byte nonce | ct+tag', () async {
      final store = SecureStore(vault: InMemoryVault(), env: const {});
      await store.seal(filePath('state.bin'), payload);
      final raw = await File(filePath('state.bin')).readAsBytes();
      expect(raw.sublist(0, 4), [0x41, 0x42, 0x58, 0x31]); // "ABX1"
      expect(raw.length, 4 + 24 + payload.length + aeadTagSize);
    });

    test('two seals of the same bytes differ (fresh random nonce)', () async {
      final store = SecureStore(vault: InMemoryVault(), env: const {});
      await store.seal(filePath('a.bin'), payload);
      await store.seal(filePath('b.bin'), payload);
      final a = await File(filePath('a.bin')).readAsBytes();
      final b = await File(filePath('b.bin')).readAsBytes();
      expect(constantTimeEquals(a, b), isFalse);
    });

    test('flipping one sealed byte makes open throw', () async {
      final store = SecureStore(vault: InMemoryVault(), env: const {});
      final path = filePath('state.bin');
      await store.seal(path, payload);
      final raw = await File(path).readAsBytes();
      raw[10] ^= 0x01; // inside the nonce/ciphertext region
      await File(path).writeAsBytes(raw);
      expect(() => store.open(path),
          throwsA(isA<AuthenticationException>()));
    });

    test('a file with bad magic throws StateError, not plaintext', () async {
      final store = SecureStore(vault: InMemoryVault(), env: const {});
      final path = filePath('state.bin');
      await store.seal(path, payload);
      final raw = await File(path).readAsBytes();
      raw[0] = 0x00;
      await File(path).writeAsBytes(raw);
      expect(() => store.open(path), throwsStateError);
    });

    test('opening with a different vault key throws (wrong-key detection)',
        () async {
      await SecureStore(vault: InMemoryVault(), env: const {})
          .seal(filePath('state.bin'), payload);
      final other = SecureStore(vault: InMemoryVault(), env: const {});
      expect(() => other.open(filePath('state.bin')),
          throwsA(isA<AuthenticationException>()));
    });
  });

  group('passphrase fallback (headless)', () {
    // Low iteration count keeps the suite fast; the 100k default is pinned
    // in crypto_aead_test and real derivations are vector-tested there.
    test('seal/open round-trips via ARXA_PASSPHRASE when no vault',
        () async {
      final store = SecureStore(
          env: const {SecureStore.passphraseEnv: 'correct horse'},
          iterations: 1000);
      await store.seal(filePath('state.bin'), payload);
      expect(await store.open(filePath('state.bin')), payload);
    });

    test('a broken vault falls through to the passphrase path', () async {
      final store = SecureStore(
          vault: BrokenVault(),
          env: const {SecureStore.passphraseEnv: 'correct horse'},
          iterations: 1000);
      await store.seal(filePath('state.bin'), payload);
      expect(await store.open(filePath('state.bin')), payload);
    });

    test('wrong passphrase makes open throw', () async {
      await SecureStore(
              env: const {SecureStore.passphraseEnv: 'correct horse'},
              iterations: 1000)
          .seal(filePath('state.bin'), payload);
      final wrong = SecureStore(
          env: const {SecureStore.passphraseEnv: 'Tr0ub4dor'},
          iterations: 1000);
      expect(() => wrong.open(filePath('state.bin')),
          throwsA(isA<AuthenticationException>()));
    });
  });

  group('fail-closed', () {
    test('no vault and no passphrase → seal refuses', () async {
      final store = SecureStore(env: const {});
      expect(() => store.seal(filePath('state.bin'), payload),
          throwsStateError);
      expect(await File(filePath('state.bin')).exists(), isFalse);
    });

    test('broken vault and no passphrase → seal refuses', () async {
      final store = SecureStore(vault: BrokenVault(), env: const {});
      expect(() => store.seal(filePath('state.bin'), payload),
          throwsStateError);
    });

    test('empty passphrase counts as unset', () async {
      final store = SecureStore(env: const {SecureStore.passphraseEnv: ''});
      expect(() => store.seal(filePath('state.bin'), payload),
          throwsStateError);
    });
  });
}
