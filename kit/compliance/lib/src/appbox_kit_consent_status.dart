import 'package:flutter/foundation.dart';

/// The acceptance status of a compliance document for one user track.
@immutable
sealed class AppBoxKitConsentStatus {
  const AppBoxKitConsentStatus();

  /// The current version has been accepted and not withdrawn.
  const factory AppBoxKitConsentStatus.accepted() = AppBoxKitConsentAccepted;

  /// A version was accepted, but not the current one — [acceptedVersion] is the
  /// stale version on record.
  const factory AppBoxKitConsentStatus.acceptedOutdatedVersion(
      String acceptedVersion) = AppBoxKitConsentAcceptedOutdatedVersion;

  /// The most recent action on record is a withdrawal.
  const factory AppBoxKitConsentStatus.withdrawn() = AppBoxKitConsentWithdrawn;

  /// No record exists for this document on this track.
  const factory AppBoxKitConsentStatus.neverAccepted() = AppBoxKitConsentNeverAccepted;

  /// The document does not require explicit acceptance.
  const factory AppBoxKitConsentStatus.notRequired() = AppBoxKitConsentNotRequired;

  /// Whether the gate is satisfied for this document. Only [AppBoxKitConsentAccepted]
  /// and [AppBoxKitConsentNotRequired] satisfy it.
  bool get isSatisfied =>
      this is AppBoxKitConsentAccepted || this is AppBoxKitConsentNotRequired;
}

/// The current version is accepted.
@immutable
final class AppBoxKitConsentAccepted extends AppBoxKitConsentStatus {
  const AppBoxKitConsentAccepted();

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitConsentAccepted && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'AppBoxKitConsentAccepted()';
}

/// A stale version ([acceptedVersion]) is accepted; the current one is not.
@immutable
final class AppBoxKitConsentAcceptedOutdatedVersion extends AppBoxKitConsentStatus {
  const AppBoxKitConsentAcceptedOutdatedVersion(this.acceptedVersion);

  /// The stale version that is on record.
  final String acceptedVersion;

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitConsentAcceptedOutdatedVersion &&
      acceptedVersion == other.acceptedVersion;

  @override
  int get hashCode => Object.hash(runtimeType, acceptedVersion);

  @override
  String toString() =>
      'AppBoxKitConsentAcceptedOutdatedVersion($acceptedVersion)';
}

/// The most recent record is a withdrawal.
@immutable
final class AppBoxKitConsentWithdrawn extends AppBoxKitConsentStatus {
  const AppBoxKitConsentWithdrawn();

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitConsentWithdrawn && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'AppBoxKitConsentWithdrawn()';
}

/// No record exists on this track.
@immutable
final class AppBoxKitConsentNeverAccepted extends AppBoxKitConsentStatus {
  const AppBoxKitConsentNeverAccepted();

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitConsentNeverAccepted && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'AppBoxKitConsentNeverAccepted()';
}

/// The document does not require explicit acceptance.
@immutable
final class AppBoxKitConsentNotRequired extends AppBoxKitConsentStatus {
  const AppBoxKitConsentNotRequired();

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitConsentNotRequired && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'AppBoxKitConsentNotRequired()';
}
