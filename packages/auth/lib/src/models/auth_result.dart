import 'auth_failure.dart';
import 'auth_session.dart';
import 'auth_user.dart';

/// The outcome of an auth operation. Sealed so callers handle both branches —
/// success carries the session, failure carries a typed [AuthFailureReason]
/// rather than a thrown exception, so ViewModels branch instead of catch.
sealed class AuthResult {
  const AuthResult();
}

/// The operation established a session.
final class AuthSuccess extends AuthResult {
  final AuthSession session;

  const AuthSuccess(this.session);

  /// Shorthand for `session.user`.
  AuthUser get user => session.user;
}

/// The operation failed. [reason] is the normalised cause; [message] is a
/// human-readable detail (safe to log, never contains the password); [cause]
/// retains the backend's original error for diagnostics.
final class AuthFailure extends AuthResult {
  final AuthFailureReason reason;
  final String message;
  final Object? cause;

  const AuthFailure(this.reason, {this.message = '', this.cause});

  @override
  String toString() => 'AuthFailure($reason${message.isEmpty ? '' : ': $message'})';
}
