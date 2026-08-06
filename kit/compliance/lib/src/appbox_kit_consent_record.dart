import 'package:flutter/foundation.dart';

/// How a consent record came to be.
enum AppBoxKitConsentMethod {
  /// The user explicitly accepted (tapped an "I agree" affordance).
  explicitTap,

  /// Consent inferred from continued use, where explicit acceptance is not
  /// required.
  implicitContinue,

  /// Imported from an external system or prior storage.
  imported,

  /// The user withdrew a prior consent.
  withdrawn,
}

/// An immutable record that a document version was accepted (or withdrawn) at a
/// point in time, optionally by a specific user.
///
/// Records are append-only: a withdrawal is a new record with
/// [AppBoxKitConsentMethod.withdrawn], not a deletion.
@immutable
final class AppBoxKitConsentRecord {
  const AppBoxKitConsentRecord({
    required this.documentId,
    required this.documentVersion,
    required this.acceptedAt,
    required this.method,
    required this.appVersion,
    this.userId,
  });

  final String documentId;

  /// The document version this record pertains to (exact-string).
  final String documentVersion;

  /// The signed-in user, or null for the anonymous track.
  final String? userId;

  /// When the record was captured.
  final DateTime acceptedAt;

  final AppBoxKitConsentMethod method;

  /// The app version at capture time, supplied by the caller. This package
  /// takes no dependency on `package_info_plus`.
  final String appVersion;

  /// Whether this record represents a withdrawal.
  bool get isWithdrawal => method == AppBoxKitConsentMethod.withdrawn;

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitConsentRecord &&
      documentId == other.documentId &&
      documentVersion == other.documentVersion &&
      userId == other.userId &&
      acceptedAt == other.acceptedAt &&
      method == other.method &&
      appVersion == other.appVersion;

  @override
  int get hashCode => Object.hash(
      documentId, documentVersion, userId, acceptedAt, method, appVersion);

  @override
  String toString() =>
      'AppBoxKitConsentRecord(documentId: $documentId, version: $documentVersion, '
      'method: $method, userId: $userId, at: $acceptedAt)';
}
