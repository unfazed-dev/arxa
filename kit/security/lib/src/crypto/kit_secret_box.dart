import 'package:flutter/foundation.dart';

import 'kit_crypto_failure.dart';

/// The plugin-neutral output of an AES-GCM encryption: a [nonce], the
/// [cipherText], and the authentication [mac].
///
/// All three parts are required to decrypt. [concatenated] packs them into a
/// single `nonce || cipherText || mac` buffer convenient for storage;
/// [KitSecretBox.fromConcatenated] reverses it.
@immutable
class KitSecretBox {
  /// Builds a box from its three parts (each defensively copied).
  KitSecretBox({
    required List<int> nonce,
    required List<int> cipherText,
    required List<int> mac,
  })  : nonce = Uint8List.fromList(nonce),
        cipherText = Uint8List.fromList(cipherText),
        mac = Uint8List.fromList(mac);

  /// Splits a [concatenated] `nonce || cipherText || mac` buffer back into a
  /// box, given the fixed [nonceLength] and [macLength] used to build it
  /// (AES-GCM defaults: 12-byte nonce, 16-byte tag).
  ///
  /// Throws [KitCryptoFailure] with [KitCryptoFailureReason.malformed] when the
  /// buffer is too short to hold both.
  factory KitSecretBox.fromConcatenated(
    List<int> bytes, {
    int nonceLength = 12,
    int macLength = 16,
  }) {
    if (bytes.length < nonceLength + macLength) {
      throw KitCryptoFailure(
        KitCryptoFailureReason.malformed,
        message: 'Concatenated box is ${bytes.length} bytes; needs at least '
            '${nonceLength + macLength}.',
      );
    }
    final cipherEnd = bytes.length - macLength;
    return KitSecretBox(
      nonce: bytes.sublist(0, nonceLength),
      cipherText: bytes.sublist(nonceLength, cipherEnd),
      mac: bytes.sublist(cipherEnd),
    );
  }

  /// The nonce / IV the ciphertext was produced with.
  final Uint8List nonce;

  /// The encrypted payload.
  final Uint8List cipherText;

  /// The authentication tag verifying [cipherText] and [nonce].
  final Uint8List mac;

  /// A single `nonce || cipherText || mac` buffer for storage / transport.
  Uint8List get concatenated =>
      Uint8List.fromList(<int>[...nonce, ...cipherText, ...mac]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KitSecretBox &&
          runtimeType == other.runtimeType &&
          listEquals(nonce, other.nonce) &&
          listEquals(cipherText, other.cipherText) &&
          listEquals(mac, other.mac);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(nonce),
        Object.hashAll(cipherText),
        Object.hashAll(mac),
      );

  @override
  String toString() =>
      'KitSecretBox(nonce: ${nonce.length}B, cipherText: ${cipherText.length}B, '
      'mac: ${mac.length}B)';
}
