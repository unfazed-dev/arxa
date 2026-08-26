import 'arxa_kit_auth_failure.dart';
import 'arxa_kit_auth_session.dart';
import 'arxa_kit_auth_user.dart';

/// The outcome of an auth operation. Sealed so callers handle both branches —
/// success carries the session, failure carries a typed [ArxaKitAuthFailureReason]
/// rather than a thrown exception, so ViewModels branch instead of catch.
sealed class ArxaKitAuthResult {
  const ArxaKitAuthResult();
}

/// The operation established a session.
final class ArxaKitAuthSuccess extends ArxaKitAuthResult {
  final ArxaKitAuthSession session;

  const ArxaKitAuthSuccess(this.session);

  /// Shorthand for `session.user`.
  ArxaKitAuthUser get user => session.user;
}

/// The operation failed. [reason] is the normalised cause; [message] is a
/// human-readable detail (safe to log, never contains the password); [cause]
/// retains the backend's original error for diagnostics.
final class ArxaKitAuthFailure extends ArxaKitAuthResult {
  final ArxaKitAuthFailureReason reason;
  final String message;
  final Object? cause;

  const ArxaKitAuthFailure(this.reason, {this.message = '', this.cause});

  @override
  String toString() => 'ArxaKitAuthFailure($reason${message.isEmpty ? '' : ': $message'})';
}
