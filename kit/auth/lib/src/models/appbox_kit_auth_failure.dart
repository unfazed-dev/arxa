/// Why a sign-in / sign-up failed, normalised across backends so UI can branch
/// without matching on backend-specific error strings. A backend maps its own
/// error codes onto these; anything unrecognised becomes [unknown].
enum AppBoxKitAuthFailureReason {
  /// Password (or OTP) did not match the identity.
  invalidCredentials,

  /// No identity exists for the supplied email/phone.
  userNotFound,

  /// Sign-up rejected because the email is already registered.
  emailAlreadyInUse,

  /// Sign-up rejected because the password fails the strength policy.
  weakPassword,

  /// The identity exists but has been disabled/banned by an operator.
  userDisabled,

  /// The session's access token has expired and could not be refreshed.
  /// Callers should route back to a sign-in screen.
  tokenExpired,

  /// The backend has this auth method turned off (e.g. OAuth not configured).
  operationNotAllowed,

  /// A transport-level failure reaching the backend.
  network,

  /// The user backed out of an interactive flow (OAuth sheet, biometric).
  cancelled,

  /// Anything the backend did not map to a specific reason.
  unknown,
}
