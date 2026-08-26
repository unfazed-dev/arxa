/// Scriptable test doubles for arxa_kit_security.
///
/// Import in tests and demos to drive the security ports without touching the
/// OS, keychain, or a real crypto backend:
///
/// ```dart
/// final biometrics = FakeArxaKitBiometricService()
///   ..script([const ArxaKitBiometricFailure(ArxaKitBiometricFailureReason.cancelled)]);
/// final pin = FakeArxaKitPinVerifier(pin: '1234');
/// final lock = ArxaKitAppLockController(biometrics: biometrics, pinVerifier: pin);
///
/// await lock.unlockWithBiometrics();      // fails → back to locked
/// final outcome = await lock.unlockWithPin('1234');
/// expect(outcome, isA<ArxaKitAppLockUnlocked>());
/// expect(lock.state, ArxaKitAppLockState.unlocked);
/// await lock.dispose();
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'src/biometric/arxa_kit_biometric_availability.dart';
import 'src/biometric/arxa_kit_biometric_result.dart';
import 'src/biometric/arxa_kit_biometric_service.dart';
import 'src/biometric/arxa_kit_biometric_type.dart';
import 'src/crypto/arxa_kit_crypto_failure.dart';
import 'src/crypto/arxa_kit_crypto_key.dart';
import 'src/crypto/arxa_kit_crypto_service.dart';
import 'src/crypto/arxa_kit_secret_box.dart';
import 'src/integrity/arxa_kit_device_integrity_service.dart';
import 'src/integrity/arxa_kit_integrity_report.dart';
import 'src/storage/arxa_kit_secure_storage_service.dart';
import 'src/app_lock/arxa_kit_pin_verifier.dart';

export 'src/biometric/arxa_kit_biometric_availability.dart';
export 'src/biometric/arxa_kit_biometric_result.dart';
export 'src/biometric/arxa_kit_biometric_service.dart';
export 'src/biometric/arxa_kit_biometric_type.dart';
export 'src/crypto/arxa_kit_crypto_failure.dart';
export 'src/crypto/arxa_kit_crypto_key.dart';
export 'src/crypto/arxa_kit_crypto_service.dart';
export 'src/crypto/arxa_kit_secret_box.dart';
export 'src/integrity/arxa_kit_device_integrity_service.dart';
export 'src/integrity/arxa_kit_integrity_report.dart';
export 'src/integrity/arxa_kit_tri_state.dart';
export 'src/storage/arxa_kit_secure_storage_service.dart';
export 'src/app_lock/arxa_kit_pin_verifier.dart';

/// A [ArxaKitBiometricService] whose availability and per-call results are scripted.
///
/// [authenticate] pops the next scripted [ArxaKitBiometricResult] (queued via
/// [script]); when the queue is empty it returns [defaultResult]. Call
/// [pauseAuthentication] to hold the next authenticate mid-flight (to exercise
/// the "unlock while unlocking" path).
class FakeArxaKitBiometricService implements ArxaKitBiometricService {
  FakeArxaKitBiometricService({
    ArxaKitBiometricAvailability availability = const ArxaKitBiometricAvailability
        .available(<ArxaKitBiometricType>{ArxaKitBiometricType.fingerprint}),
    ArxaKitBiometricResult defaultResult = const ArxaKitBiometricSuccess(),
  })  : _availability = availability,
        _defaultResult = defaultResult;

  ArxaKitBiometricAvailability _availability;
  ArxaKitBiometricResult _defaultResult;
  final List<ArxaKitBiometricResult> _results = <ArxaKitBiometricResult>[];
  Completer<void>? _pause;

  /// Number of [availability] calls.
  int availabilityCallCount = 0;

  /// Number of [authenticate] calls.
  int authenticateCallCount = 0;

  /// The [reason] passed to the most recent [authenticate].
  String? lastReason;

  /// Sets what [availability] returns.
  void setAvailability(ArxaKitBiometricAvailability availability) =>
      _availability = availability;

  /// Queues [results] to be returned by successive [authenticate] calls.
  void script(List<ArxaKitBiometricResult> results) => _results
    ..clear()
    ..addAll(results);

  /// Sets the result used once the scripted queue is exhausted.
  void setDefaultResult(ArxaKitBiometricResult result) => _defaultResult = result;

  /// Holds the next [authenticate] until the returned completer is completed.
  Completer<void> pauseAuthentication() => _pause = Completer<void>();

  @override
  Future<ArxaKitBiometricAvailability> availability() async {
    availabilityCallCount++;
    return _availability;
  }

  @override
  Future<ArxaKitBiometricResult> authenticate({required String reason}) async {
    authenticateCallCount++;
    lastReason = reason;
    final pause = _pause;
    _pause = null;
    if (pause != null) await pause.future;
    if (_results.isNotEmpty) return _results.removeAt(0);
    return _defaultResult;
  }
}

/// An in-memory [ArxaKitSecureStorageService] with per-operation call counts.
class FakeArxaKitSecureStorageService implements ArxaKitSecureStorageService {
  final Map<String, String> _data = <String, String>{};

  /// Call counts for each operation.
  int readCallCount = 0;
  int writeCallCount = 0;
  int deleteCallCount = 0;
  int containsKeyCallCount = 0;
  int deleteAllCallCount = 0;

  /// A read-only view of the stored entries.
  Map<String, String> get snapshot => Map<String, String>.unmodifiable(_data);

  @override
  Future<String?> read(String key) async {
    readCallCount++;
    return _data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writeCallCount++;
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deleteCallCount++;
    _data.remove(key);
  }

  @override
  Future<bool> containsKey(String key) async {
    containsKeyCallCount++;
    return _data.containsKey(key);
  }

  @override
  Future<void> deleteAll() async {
    deleteAllCallCount++;
    _data.clear();
  }
}

/// A deterministic, reversible [ArxaKitCryptoService] for tests — **not** real
/// cryptography.
///
/// "Encryption" XORs the plaintext with a key-derived keystream and stores a
/// deterministic tag; [decryptBytes] recomputes the tag and throws
/// [ArxaKitCryptoFailure] with [ArxaKitCryptoFailureReason.authentication] on mismatch
/// (wrong key) — so wrong-key and tamper paths behave like the real backend.
/// Set [failNextDecrypt] to force the next decrypt to fail.
class FakeArxaKitCryptoService implements ArxaKitCryptoService {
  int _counter = 0;

  /// Call counts.
  int encryptCallCount = 0;
  int decryptCallCount = 0;

  /// When true, the next [decryptBytes] throws an authentication failure, then
  /// clears back to false.
  bool failNextDecrypt = false;

  @override
  Future<ArxaKitCryptoKey> generateKey() async => ArxaKitCryptoKey(_freshBytes(32));

  @override
  List<int> generateNonce() => _freshBytes(12);

  @override
  Future<ArxaKitSecretBox> encryptBytes(
    List<int> data, {
    required ArxaKitCryptoKey key,
    List<int>? nonce,
  }) async {
    encryptCallCount++;
    final stream = _keystream(key.bytes, data.length);
    final cipher = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      cipher[i] = data[i] ^ stream[i];
    }
    return ArxaKitSecretBox(
      nonce: nonce ?? generateNonce(),
      cipherText: cipher,
      mac: _tag(key.bytes, data),
    );
  }

  @override
  Future<Uint8List> decryptBytes(
    ArxaKitSecretBox box, {
    required ArxaKitCryptoKey key,
  }) async {
    decryptCallCount++;
    if (failNextDecrypt) {
      failNextDecrypt = false;
      throw const ArxaKitCryptoFailure(
        ArxaKitCryptoFailureReason.authentication,
        message: 'Fake: forced decrypt failure.',
      );
    }
    final stream = _keystream(key.bytes, box.cipherText.length);
    final plain = Uint8List(box.cipherText.length);
    for (var i = 0; i < box.cipherText.length; i++) {
      plain[i] = box.cipherText[i] ^ stream[i];
    }
    if (!_bytesEqual(_tag(key.bytes, plain), box.mac)) {
      throw const ArxaKitCryptoFailure(
        ArxaKitCryptoFailureReason.authentication,
        message: 'Fake: tag mismatch (wrong key or tampered).',
      );
    }
    return plain;
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
  }) async =>
      utf8.decode(await decryptBytes(box, key: key));

  @override
  Future<Uint8List> sha256(List<int> data) async => _digest(data);

  @override
  Future<Uint8List> hmacSha256(
    List<int> data, {
    required ArxaKitCryptoKey key,
  }) async =>
      _digest(key.bytes, data);

  Uint8List _freshBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = (_counter + i * 31) & 0xFF;
    }
    _counter++;
    return out;
  }

  static Uint8List _keystream(List<int> key, int length) {
    final out = Uint8List(length);
    if (key.isEmpty) return out;
    for (var i = 0; i < length; i++) {
      out[i] = key[i % key.length];
    }
    return out;
  }

  static Uint8List _tag(List<int> key, List<int> data) =>
      Uint8List.sublistView(_digest(key, data), 0, 16);

  static Uint8List _digest(List<int> a, [List<int> b = const <int>[]]) {
    var h = 0x9e3779b1;
    void mix(List<int> data) {
      for (final byte in data) {
        h = ((h ^ byte) * 0x01000193) & 0xFFFFFFFF;
      }
    }

    mix(a);
    mix(const <int>[0]);
    mix(b);
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      h = ((h * 0x01000193) + i) & 0xFFFFFFFF;
      out[i] = (h >> ((i % 4) * 8)) & 0xFF;
    }
    return out;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A [ArxaKitPinVerifier] holding a plaintext PIN in memory, with optional scripted
/// [verifyPin] results and call counts.
class FakeArxaKitPinVerifier implements ArxaKitPinVerifier {
  FakeArxaKitPinVerifier({String? pin}) : _pin = pin;

  String? _pin;
  final List<bool> _scripted = <bool>[];

  /// Call counts.
  int hasPinCallCount = 0;
  int setPinCallCount = 0;
  int verifyPinCallCount = 0;
  int clearPinCallCount = 0;

  /// The PIN passed to the most recent [verifyPin].
  String? lastVerified;

  /// Queues [results] to be returned by successive [verifyPin] calls, ahead of
  /// the stored-PIN comparison.
  void script(List<bool> results) => _scripted
    ..clear()
    ..addAll(results);

  @override
  Future<bool> hasPin() async {
    hasPinCallCount++;
    return _pin != null;
  }

  @override
  Future<void> setPin(String pin) async {
    setPinCallCount++;
    _pin = pin;
  }

  @override
  Future<bool> verifyPin(String pin) async {
    verifyPinCallCount++;
    lastVerified = pin;
    if (_scripted.isNotEmpty) return _scripted.removeAt(0);
    return _pin != null && pin == _pin;
  }

  @override
  Future<void> clearPin() async {
    clearPinCallCount++;
    _pin = null;
  }
}

/// A [ArxaKitDeviceIntegrityService] that returns a scripted [ArxaKitIntegrityReport]
/// (or throws a scripted error).
class FakeArxaKitDeviceIntegrityService implements ArxaKitDeviceIntegrityService {
  FakeArxaKitDeviceIntegrityService({
    ArxaKitIntegrityReport report = ArxaKitIntegrityReport.unknown,
  }) : _report = report;

  ArxaKitIntegrityReport _report;
  Object? _error;

  /// Number of [check] calls.
  int checkCallCount = 0;

  /// Sets the report [check] returns (and clears any scripted error).
  void setReport(ArxaKitIntegrityReport report) {
    _report = report;
    _error = null;
  }

  /// Makes the next [check] calls throw [error].
  void setError(Object error) => _error = error;

  @override
  Future<ArxaKitIntegrityReport> check() async {
    checkCallCount++;
    final error = _error;
    if (error != null) throw error;
    return _report;
  }
}
