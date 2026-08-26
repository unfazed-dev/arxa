import 'dart:io';

import 'process.dart';

/// The OS credential vault. The daemon is pure Dart, so `flutter_secure_storage`
/// is not available — this is the thinnest honest seam over each platform's
/// native vault. 8.6: never hand-rolled crypto; secrets live behind the OS.
///
/// Backends:
/// - macOS: [KeychainVault] shells out to `/usr/bin/security`.
/// - Windows: TODO — adapter over `cmdkey` (Credential Manager) or DPAPI via
///   `rundll32`; same [Vault] shape.
/// - Linux: TODO — adapter over `secret-tool` (libsecret / Secret Service API);
///   same [Vault] shape.
abstract class Vault {
  /// Reads the secret stored under [key], or null when absent.
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing any existing entry.
  Future<void> write(String key, String value);

  /// Removes the entry for [key]; a no-op when absent.
  Future<void> delete(String key);

  /// Lists every key this vault holds for the service (secrets NOT included —
  /// enumeration is for state hydration, not exfiltration).
  Future<List<String>> readAllKeys();
}

/// In-memory [Vault] for tests and headless dev — never for production secrets.
class InMemoryVault implements Vault {
  final _entries = <String, String>{};

  @override
  Future<String?> read(String key) async => _entries[key];

  @override
  Future<void> write(String key, String value) async {
    _entries[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _entries.remove(key);
  }

  @override
  Future<List<String>> readAllKeys() async => List.unmodifiable(_entries.keys);
}

/// macOS Keychain via `/usr/bin/security` (find/add/delete-generic-password).
///
/// Every entry carries the service name [service] (default `arxa`) and the
/// vault key as the account, so entries are namespaced and enumerable via
/// `security dump-keychain` without a side-car index — mirroring the key layout
/// the legacy app used inside `flutter_secure_storage`.
///
/// The [ProcessRunner] seam keeps this unit-testable without touching a real
/// keychain: tests assert the exact argv and feed canned stdout/exit codes.
class KeychainVault implements Vault {
  KeychainVault({this.service = 'arxa', ProcessRunner? runner})
      : _runner = runner ?? const RealProcessRunner();

  static const binary = '/usr/bin/security';

  /// `security find-generic-password` exit code for "item not found".
  static const errSecItemNotFound = 44;

  final String service;
  final ProcessRunner _runner;

  @override
  Future<String?> read(String key) async {
    final res = await _runner.run(binary, [
      'find-generic-password',
      '-s', service,
      '-a', key,
      '-w', // print the password only, on stdout
    ]);
    if (res.exitCode == errSecItemNotFound) return null;
    if (!res.ok) {
      throw StateError('keychain read failed for "$key": ${res.stderr.trim()}');
    }
    return res.stdout.endsWith('\n')
        ? res.stdout.substring(0, res.stdout.length - 1)
        : res.stdout;
  }

  @override
  Future<void> write(String key, String value) async {
    final res = await _runner.run(binary, [
      'add-generic-password',
      '-U', // update in place when the entry already exists
      '-s', service,
      '-a', key,
      '-w', value,
    ]);
    if (!res.ok) {
      throw StateError('keychain write failed for "$key": ${res.stderr.trim()}');
    }
  }

  @override
  Future<void> delete(String key) async {
    final res = await _runner.run(binary, [
      'delete-generic-password',
      '-s', service,
      '-a', key,
    ]);
    if (!res.ok && res.exitCode != errSecItemNotFound) {
      throw StateError('keychain delete failed for "$key": ${res.stderr.trim()}');
    }
  }

  @override
  Future<List<String>> readAllKeys() async {
    final res = await _runner.run(binary, ['dump-keychain']);
    if (!res.ok) {
      throw StateError('keychain dump failed: ${res.stderr.trim()}');
    }
    final keys = <String>[];
    String? acct;
    var inGeneric = false;
    for (final line in res.stdout.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('class:')) {
        inGeneric = trimmed.contains('"genp"');
        acct = null;
      } else if (inGeneric && trimmed.startsWith('"acct"<blob>=')) {
        acct = _blobValue(trimmed);
      } else if (inGeneric && trimmed.startsWith('"svce"<blob>=')) {
        if (_blobValue(trimmed) == service && acct != null) {
          keys.add(acct);
        }
      }
    }
    return keys;
  }

  static String _blobValue(String line) {
    // `"acct"<blob>="value"` — take the text after `=`; quoted values keep
    // their quotes, which we strip.
    var v = line.substring(line.indexOf('=') + 1).trim();
    if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
      v = v.substring(1, v.length - 1);
    }
    return v;
  }
}

/// Picks the honest vault for the current platform.
Vault platformVault({ProcessRunner? runner}) {
  if (Platform.isMacOS) return KeychainVault(runner: runner);
  throw UnsupportedError(
    'no vault backend for ${Platform.operatingSystem} yet — '
    'see the TODOs on Vault (Windows: Credential Manager, Linux: libsecret)',
  );
}
