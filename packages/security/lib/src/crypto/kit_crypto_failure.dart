/// Why a [KitCryptoService] decrypt / parse operation failed.
enum KitCryptoFailureReason {
  /// The ciphertext failed authentication (wrong key, or tampered data). This
  /// is the security-critical case: the plaintext must not be trusted.
  authentication,

  /// The input was structurally invalid (e.g. a truncated concatenated box, or
  /// a key of the wrong length).
  malformed,

  /// An unclassified cryptographic error.
  unknown,
}

/// A typed failure raised by [KitCryptoService] decrypt / parse operations.
///
/// Thrown (never returned) so a successful decrypt can hand back plaintext
/// directly. Callers catch this to distinguish a tampered/[authentication]
/// failure from a merely [malformed] input.
class KitCryptoFailure implements Exception {
  const KitCryptoFailure(this.reason, {this.message, this.cause});

  /// The typed reason.
  final KitCryptoFailureReason reason;

  /// A human-readable description, if any.
  final String? message;

  /// The originating error, if any.
  final Object? cause;

  @override
  String toString() =>
      'KitCryptoFailure(${reason.name}${message == null ? '' : ': $message'})';
}
