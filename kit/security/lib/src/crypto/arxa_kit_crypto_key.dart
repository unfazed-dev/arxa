import 'package:flutter/foundation.dart';

/// A symmetric key held by the app, plugin-neutral (no `cryptography`
/// `SecretKey` leaks through the port).
///
/// Wraps raw key bytes. For AES-GCM-256 the expected length is 32 bytes; obtain
/// one from [ArxaKitCryptoService.generateKey] or reconstruct from stored bytes via
/// the constructor.
@immutable
class ArxaKitCryptoKey {
  /// Wraps [bytes] (defensively copied) as a key.
  ArxaKitCryptoKey(List<int> bytes) : bytes = Uint8List.fromList(bytes);

  /// The raw key material.
  final Uint8List bytes;

  /// Key length in bytes.
  int get lengthInBytes => bytes.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArxaKitCryptoKey &&
          runtimeType == other.runtimeType &&
          listEquals(bytes, other.bytes);

  @override
  int get hashCode => Object.hashAll(bytes);

  @override
  String toString() => 'ArxaKitCryptoKey(${bytes.length} bytes)';
}
