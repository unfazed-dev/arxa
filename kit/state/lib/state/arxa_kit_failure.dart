import 'package:meta/meta.dart';

/// A normalized failure carried by [ArxaKitError].
///
/// [code] is the stable, i18n-friendly identifier (e.g. `network`,
/// `unauthorized`); [message] is a human-readable fallback. Hosts key
/// localization off [code] and fall back to [message].
///
/// Equality intentionally ignores [stackTrace] (stack traces are not
/// value-comparable) but includes [cause].
@immutable
class ArxaKitFailure {
  const ArxaKitFailure({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
  });

  /// Wraps an arbitrary error/exception into a [ArxaKitFailure]. Returns [error]
  /// unchanged when it is already a [ArxaKitFailure].
  factory ArxaKitFailure.from(Object error, [StackTrace? stackTrace]) {
    if (error is ArxaKitFailure) return error;
    return ArxaKitFailure(
      code: ArxaKitFailureCode.unknown,
      message: error.toString(),
      cause: error,
      stackTrace: stackTrace,
    );
  }

  /// Stable, i18n-friendly identifier. See [ArxaKitFailureCode] for well-known
  /// values; hosts may define their own.
  final String code;

  /// Human-readable fallback message.
  final String message;

  /// The originating error/exception, if any.
  final Object? cause;

  /// The originating stack trace, if any. Excluded from equality.
  final StackTrace? stackTrace;

  ArxaKitFailure copyWith({
    String? code,
    String? message,
    Object? cause,
    StackTrace? stackTrace,
  }) =>
      ArxaKitFailure(
        code: code ?? this.code,
        message: message ?? this.message,
        cause: cause ?? this.cause,
        stackTrace: stackTrace ?? this.stackTrace,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArxaKitFailure &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          message == other.message &&
          cause == other.cause;

  @override
  int get hashCode => Object.hash(runtimeType, code, message, cause);

  @override
  String toString() => 'ArxaKitFailure(code: $code, message: $message)';
}

/// Well-known [ArxaKitFailure.code] values. Hosts may define additional codes.
abstract final class ArxaKitFailureCode {
  static const String unknown = 'unknown';
  static const String network = 'network';
  static const String timeout = 'timeout';
  static const String unauthorized = 'unauthorized';
  static const String notFound = 'not_found';
  static const String validation = 'validation';
  static const String cancelled = 'cancelled';
}
