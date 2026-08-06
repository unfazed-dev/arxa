/// What a caller hands to a sign-in / sign-up method. Sealed so new credential
/// kinds (magic link, phone OTP) can be added as variants without loosening
/// the method signatures. Today the port takes [AppBoxKitEmailPasswordCredentials]
/// directly; OAuth flows have their own methods (`signInWithApple` /
/// `signInWithGoogle`) because they carry no caller-supplied secret.
sealed class AppBoxKitAuthCredentials {
  const AppBoxKitAuthCredentials();
}

/// Email + password. The password is never stored by the in-memory backend
/// beyond the process lifetime and is never logged.
final class AppBoxKitEmailPasswordCredentials extends AppBoxKitAuthCredentials {
  final String email;
  final String password;

  const AppBoxKitEmailPasswordCredentials({
    required this.email,
    required this.password,
  });
}
