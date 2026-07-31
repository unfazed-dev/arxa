import 'package:flutter/foundation.dart';

/// The acceptance status of a compliance document for one user track.
@immutable
sealed class KitConsentStatus {
  const KitConsentStatus();

  /// The current version has been accepted and not withdrawn.
  const factory KitConsentStatus.accepted() = KitConsentAccepted;

  /// A version was accepted, but not the current one — [acceptedVersion] is the
  /// stale version on record.
  const factory KitConsentStatus.acceptedOutdatedVersion(
      String acceptedVersion) = KitConsentAcceptedOutdatedVersion;

  /// The most recent action on record is a withdrawal.
  const factory KitConsentStatus.withdrawn() = KitConsentWithdrawn;

  /// No record exists for this document on this track.
  const factory KitConsentStatus.neverAccepted() = KitConsentNeverAccepted;

  /// The document does not require explicit acceptance.
  const factory KitConsentStatus.notRequired() = KitConsentNotRequired;

  /// Whether the gate is satisfied for this document. Only [KitConsentAccepted]
  /// and [KitConsentNotRequired] satisfy it.
  bool get isSatisfied =>
      this is KitConsentAccepted || this is KitConsentNotRequired;
}

/// The current version is accepted.
@immutable
final class KitConsentAccepted extends KitConsentStatus {
  const KitConsentAccepted();

  @override
  bool operator ==(Object other) =>
      other is KitConsentAccepted && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'KitConsentAccepted()';
}

/// A stale version ([acceptedVersion]) is accepted; the current one is not.
@immutable
final class KitConsentAcceptedOutdatedVersion extends KitConsentStatus {
  const KitConsentAcceptedOutdatedVersion(this.acceptedVersion);

  /// The stale version that is on record.
  final String acceptedVersion;

  @override
  bool operator ==(Object other) =>
      other is KitConsentAcceptedOutdatedVersion &&
      acceptedVersion == other.acceptedVersion;

  @override
  int get hashCode => Object.hash(runtimeType, acceptedVersion);

  @override
  String toString() =>
      'KitConsentAcceptedOutdatedVersion($acceptedVersion)';
}

/// The most recent record is a withdrawal.
@immutable
final class KitConsentWithdrawn extends KitConsentStatus {
  const KitConsentWithdrawn();

  @override
  bool operator ==(Object other) =>
      other is KitConsentWithdrawn && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'KitConsentWithdrawn()';
}

/// No record exists on this track.
@immutable
final class KitConsentNeverAccepted extends KitConsentStatus {
  const KitConsentNeverAccepted();

  @override
  bool operator ==(Object other) =>
      other is KitConsentNeverAccepted && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'KitConsentNeverAccepted()';
}

/// The document does not require explicit acceptance.
@immutable
final class KitConsentNotRequired extends KitConsentStatus {
  const KitConsentNotRequired();

  @override
  bool operator ==(Object other) =>
      other is KitConsentNotRequired && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'KitConsentNotRequired()';
}
