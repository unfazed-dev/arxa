import 'package:flutter/foundation.dart';

/// The acceptance status of a compliance document for one user track.
@immutable
sealed class ArxaKitConsentStatus {
  const ArxaKitConsentStatus();

  /// The current version has been accepted and not withdrawn.
  const factory ArxaKitConsentStatus.accepted() = ArxaKitConsentAccepted;

  /// A version was accepted, but not the current one — [acceptedVersion] is the
  /// stale version on record.
  const factory ArxaKitConsentStatus.acceptedOutdatedVersion(
      String acceptedVersion) = ArxaKitConsentAcceptedOutdatedVersion;

  /// The most recent action on record is a withdrawal.
  const factory ArxaKitConsentStatus.withdrawn() = ArxaKitConsentWithdrawn;

  /// No record exists for this document on this track.
  const factory ArxaKitConsentStatus.neverAccepted() = ArxaKitConsentNeverAccepted;

  /// The document does not require explicit acceptance.
  const factory ArxaKitConsentStatus.notRequired() = ArxaKitConsentNotRequired;

  /// Whether the gate is satisfied for this document. Only [ArxaKitConsentAccepted]
  /// and [ArxaKitConsentNotRequired] satisfy it.
  bool get isSatisfied =>
      this is ArxaKitConsentAccepted || this is ArxaKitConsentNotRequired;
}

/// The current version is accepted.
@immutable
final class ArxaKitConsentAccepted extends ArxaKitConsentStatus {
  const ArxaKitConsentAccepted();

  @override
  bool operator ==(Object other) =>
      other is ArxaKitConsentAccepted && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'ArxaKitConsentAccepted()';
}

/// A stale version ([acceptedVersion]) is accepted; the current one is not.
@immutable
final class ArxaKitConsentAcceptedOutdatedVersion extends ArxaKitConsentStatus {
  const ArxaKitConsentAcceptedOutdatedVersion(this.acceptedVersion);

  /// The stale version that is on record.
  final String acceptedVersion;

  @override
  bool operator ==(Object other) =>
      other is ArxaKitConsentAcceptedOutdatedVersion &&
      acceptedVersion == other.acceptedVersion;

  @override
  int get hashCode => Object.hash(runtimeType, acceptedVersion);

  @override
  String toString() =>
      'ArxaKitConsentAcceptedOutdatedVersion($acceptedVersion)';
}

/// The most recent record is a withdrawal.
@immutable
final class ArxaKitConsentWithdrawn extends ArxaKitConsentStatus {
  const ArxaKitConsentWithdrawn();

  @override
  bool operator ==(Object other) =>
      other is ArxaKitConsentWithdrawn && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'ArxaKitConsentWithdrawn()';
}

/// No record exists on this track.
@immutable
final class ArxaKitConsentNeverAccepted extends ArxaKitConsentStatus {
  const ArxaKitConsentNeverAccepted();

  @override
  bool operator ==(Object other) =>
      other is ArxaKitConsentNeverAccepted && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'ArxaKitConsentNeverAccepted()';
}

/// The document does not require explicit acceptance.
@immutable
final class ArxaKitConsentNotRequired extends ArxaKitConsentStatus {
  const ArxaKitConsentNotRequired();

  @override
  bool operator ==(Object other) =>
      other is ArxaKitConsentNotRequired && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'ArxaKitConsentNotRequired()';
}
