import 'appbox_kit_auth_user.dart';

/// A live session: the [user] plus the tokens a real backend issues. Token
/// fields are null on the in-memory default (nothing local needs to verify
/// them). [expiresAt] is what makes token-expiry testable — see
/// [isExpiredAt].
class AppBoxKitAuthSession {
  final AppBoxKitAuthUser user;
  final String? accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  const AppBoxKitAuthSession({
    required this.user,
    this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  /// Whether the access token is expired at [now]. False when [expiresAt] is
  /// null (a session with no known expiry never auto-expires). [now] is a
  /// parameter (not `DateTime.now()`) so tests stay deterministic.
  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !now.isBefore(expiresAt!);

  AppBoxKitAuthSession copyWith({
    AppBoxKitAuthUser? user,
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
  }) =>
      AppBoxKitAuthSession(
        user: user ?? this.user,
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        expiresAt: expiresAt ?? this.expiresAt,
      );
}
