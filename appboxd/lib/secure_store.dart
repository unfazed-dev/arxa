/// Encryption-at-rest for appboxd's own sensitive state (plan P1): vault
/// material, licence file, memory/analytics store. XChaCha20-Poly1305 —
/// the age-class construction the plan names.
///
/// File format (single envelope, no header fields beyond what's needed):
///
/// ```
/// magic "ABX1" | 24-byte nonce | ciphertext | 16-byte Poly1305 tag
/// ```
///
/// Key resolution order (first match wins):
/// 1. Random 32-byte data key from the OS vault ([Vault] key
///    [SecureStore.vaultKeyName], hex-encoded; generated on first use).
/// 2. Passphrase via PBKDF2-HMAC-SHA256 — env `APPBOX_PASSPHRASE` for
///    headless hosts with no vault backend. The passphrase key is derived
///    with a fixed application salt (`appbox.state.v1`): acceptable for the
///    documented headless fallback, but the vault path is preferred — a
///    random data key has no passphrase-guessing surface.
///
/// kimitail: if the OS vault is unavailable AND no passphrase is set, we
/// refuse to seal — fail closed, never store plaintext silently. (Ceiling:
/// on hosts without a vault backend the operator MUST export
/// APPBOX_PASSPHRASE or state stays unwritable; that is the intended
/// behaviour, not a gap.)
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'crypto_aead.dart';
import 'vault.dart';

class SecureStore {
  SecureStore({this._vault, Map<String, String>? env, int? iterations})
      : _env = env ?? Platform.environment,
        _pbkdf2Iterations = iterations ?? pbkdf2Iterations;

  /// Vault key under which the random data key is stored (hex-encoded).
  static const vaultKeyName = 'appbox.state_key';

  /// Passphrase env var for headless hosts without an OS vault.
  static const passphraseEnv = 'APPBOX_PASSPHRASE';

  static const _magic = [0x41, 0x42, 0x58, 0x31]; // "ABX1"
  static final _passphraseSalt =
      Uint8List.fromList('appbox.state.v1'.codeUnits);

  final Vault? _vault;
  final Map<String, String> _env;
  final int _pbkdf2Iterations;
  Uint8List? _key;

  /// Resolves (and caches) the 32-byte data key. Fails closed when neither
  /// vault nor passphrase is available.
  Future<Uint8List> _resolveKey() async {
    final cached = _key;
    if (cached != null) return cached;

    final vault = _vault;
    if (vault != null) {
      try {
        final stored = await vault.read(vaultKeyName);
        if (stored != null) {
          return _key = hexDecode(stored);
        }
        final generated = randomBytes(32);
        await vault.write(vaultKeyName, hexEncode(generated));
        return _key = generated;
      } catch (_) {
        // Vault present but broken (denied, unsupported platform) — fall
        // through to the passphrase path rather than dying here.
      }
    }

    final passphrase = _env[passphraseEnv];
    if (passphrase != null && passphrase.isNotEmpty) {
      return _key = pbkdf2HmacSha256(Uint8List.fromList(passphrase.codeUnits),
          _passphraseSalt, _pbkdf2Iterations, 32);
    }

    throw StateError(
      'no encryption key source: OS vault unavailable and '
      '\$$passphraseEnv not set — refusing to write state unencrypted',
    );
  }

  /// Encrypts [bytes] and writes the `ABX1` envelope to [path] (0600).
  /// A fresh 24-byte nonce is drawn from Random.secure per call, so rewriting
  /// the same file is nonce-safe.
  Future<void> seal(String path, Uint8List bytes) async {
    final key = await _resolveKey();
    final nonce = randomBytes(xchachaNonceSize);
    final sealed = sealXChaCha20Poly1305(key, nonce, bytes);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      Uint8List.fromList([..._magic, ...nonce, ...sealed]),
      flush: true,
    );
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', path]);
    }
  }

  /// Reads and decrypts the envelope at [path]. Throws
  /// [AuthenticationException] on tamper/wrong key and [StateError] on a
  /// malformed (non-ABX1) file.
  Future<Uint8List> open(String path) async {
    final raw = await File(path).readAsBytes();
    const header = 4 + xchachaNonceSize;
    if (raw.length < header + aeadTagSize) {
      throw StateError('not an ABX1 sealed file (too short): $path');
    }
    for (var i = 0; i < 4; i++) {
      if (raw[i] != _magic[i]) {
        throw StateError('not an ABX1 sealed file (bad magic): $path');
      }
    }
    final key = await _resolveKey();
    final nonce = Uint8List.sublistView(raw, 4, header);
    final body = Uint8List.sublistView(raw, header);
    return openXChaCha20Poly1305(key, nonce, body);
  }
}

/// A [Vault] over a single [SecureStore]-sealed JSON file — the credential
/// fallback for hosts with no OS vault backend (the Windows/Linux TODOs on
/// [Vault]). The whole map is re-sealed on every mutation; a credential store
/// is small, so rewriting is the honest simple thing.
class SealedFileVault implements Vault {
  SealedFileVault(this.path, this._store);

  final String path;
  final SecureStore _store;
  Map<String, String>? _cache;

  Future<Map<String, String>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;
    if (!File(path).existsSync()) return _cache = {};
    final plain = await _store.open(path);
    final decoded = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    return _cache = decoded.map((k, v) => MapEntry(k, v as String));
  }

  Future<void> _flush(Map<String, String> entries) async {
    _cache = entries;
    await _store.seal(
        path, Uint8List.fromList(utf8.encode(jsonEncode(entries))));
  }

  @override
  Future<String?> read(String key) async => (await _load())[key];

  @override
  Future<void> write(String key, String value) async {
    final entries = await _load();
    await _flush({...entries, key: value});
  }

  @override
  Future<void> delete(String key) async {
    final entries = await _load();
    if (!entries.containsKey(key)) return;
    await _flush({...entries}..remove(key));
  }

  @override
  Future<List<String>> readAllKeys() async =>
      List.unmodifiable((await _load()).keys);
}
