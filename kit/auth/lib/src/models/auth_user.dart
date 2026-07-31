/// The signed-in identity, backend-agnostic. [id] is whatever the backend
/// considers a stable primary key (a uid on a real backend; a deterministic
/// local key on the in-memory default). Nothing here carries a token — that
/// lives on [AuthSession] — so a `null` [AuthUser] is the only "signed out"
/// signal the stream needs to emit.
class AuthUser {
  final String id;
  final String? email;
  final String? displayName;
  final bool isAnonymous;
  final Map<String, dynamic> metadata;

  const AuthUser({
    required this.id,
    this.email,
    this.displayName,
    this.isAnonymous = false,
    this.metadata = const {},
  });

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.id == id &&
      other.email == email &&
      other.displayName == displayName &&
      other.isAnonymous == isAnonymous;

  @override
  int get hashCode => Object.hash(id, email, displayName, isAnonymous);

  @override
  String toString() =>
      'AuthUser(id: $id, email: $email, isAnonymous: $isAnonymous)';
}
