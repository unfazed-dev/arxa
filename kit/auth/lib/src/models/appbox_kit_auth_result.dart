import 'appbox_kit_auth_failure.dart';
import 'appbox_kit_auth_session.dart';
import 'appbox_kit_auth_user.dart';

/// The outcome of an auth operation. Sealed so callers handle both branches —
/// success carries the session, failure carries a typed [AppBoxKitAuthFailureReason]
/// rather than a thrown exception, so ViewModels branch instead of catch.
sealed class AppBoxKitAuthResult {
  const AppBoxKitAuthResult();
}

/// The operation established a session.
final class AppBoxKitAuthSuccess extends AppBoxKitAuthResult {
  final AppBoxKitAuthSession session;

  const AppBoxKitAuthSuccess(this.session);

  /// Shorthand for `session.user`.
  AppBoxKitAuthUser get user => session.user;
}

/// The operation failed. [reason] is the normalised cause; [message] is a
/// human-readable detail (safe to log, never contains the password); [cause]
/// retains the backend's original error for diagnostics.
final class AppBoxKitAuthFailure extends AppBoxKitAuthResult {
  final AppBoxKitAuthFailureReason reason;
  final String message;
  final Object? cause;

  const AppBoxKitAuthFailure(this.reason, {this.message = '', this.cause});

  @override
  String toString() => 'AppBoxKitAuthFailure($reason${message.isEmpty ? '' : ': $message'})';
}
