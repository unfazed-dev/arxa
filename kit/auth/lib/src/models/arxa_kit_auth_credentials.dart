/// What a caller hands to a sign-in / sign-up method. Sealed so new credential
/// kinds (magic link, phone OTP) can be added as variants without loosening
/// the method signatures. Today the port takes [ArxaKitEmailPasswordCredentials]
/// directly; OAuth flows have their own methods (`signInWithApple` /
/// `signInWithGoogle`) because they carry no caller-supplied secret.
sealed class ArxaKitAuthCredentials {
  const ArxaKitAuthCredentials();
}

/// Email + password. The password is never stored by the in-memory backend
/// beyond the process lifetime and is never logged.
final class ArxaKitEmailPasswordCredentials extends ArxaKitAuthCredentials {
  final String email;
  final String password;

  const ArxaKitEmailPasswordCredentials({
    required this.email,
    required this.password,
  });
}
