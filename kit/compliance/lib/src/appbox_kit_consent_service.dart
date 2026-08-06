import 'dart:async';

import 'package:flutter/foundation.dart';

import 'appbox_kit_compliance_document.dart';
import 'appbox_kit_compliance_registry.dart';
import 'appbox_kit_consent_record.dart';
import 'appbox_kit_consent_status.dart';
import 'appbox_kit_consent_store.dart';

/// A status change emitted on [AppBoxKitConsentService.statusChanges].
@immutable
final class AppBoxKitConsentStatusChange {
  const AppBoxKitConsentStatusChange({required this.document, required this.status});

  final AppBoxKitComplianceDocument document;
  final AppBoxKitConsentStatus status;

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitConsentStatusChange &&
      document == other.document &&
      status == other.status;

  @override
  int get hashCode => Object.hash(document, status);

  @override
  String toString() => 'AppBoxKitConsentStatusChange(${document.id}: $status)';
}

/// Reads and mutates consent for a single user track — the [userId] supplied at
/// construction (null = the anonymous track) — on top of a [AppBoxKitConsentStore]
/// and a [AppBoxKitComplianceRegistry].
///
/// [accept] and [withdraw] write to the store and push a
/// [AppBoxKitConsentStatusChange] on the broadcast [statusChanges] stream. Call
/// [dispose] to release that stream.
class AppBoxKitConsentService {
  AppBoxKitConsentService({
    required AppBoxKitConsentStore store,
    required AppBoxKitComplianceRegistry registry,
    this.userId,
  })  : _store = store,
        _registry = registry;

  final AppBoxKitConsentStore _store;
  final AppBoxKitComplianceRegistry _registry;

  /// The user track this service reads and writes (null = anonymous).
  final String? userId;

  final StreamController<AppBoxKitConsentStatusChange> _changes =
      StreamController<AppBoxKitConsentStatusChange>.broadcast();

  /// Status changes produced by [accept] / [withdraw] on this service.
  Stream<AppBoxKitConsentStatusChange> get statusChanges => _changes.stream;

  /// The consent status of [document] on this service's track.
  ///
  /// A document that does not require explicit acceptance is always
  /// [AppBoxKitConsentNotRequired], irrespective of any implicit records.
  Future<AppBoxKitConsentStatus> statusFor(AppBoxKitComplianceDocument document) async {
    if (!document.requiresExplicitAcceptance) {
      return const AppBoxKitConsentStatus.notRequired();
    }
    final latest = await _store.latestFor(document.id, userId: userId);
    if (latest == null) return const AppBoxKitConsentStatus.neverAccepted();
    if (latest.method == AppBoxKitConsentMethod.withdrawn) {
      return const AppBoxKitConsentStatus.withdrawn();
    }
    if (latest.documentVersion == document.version) {
      return const AppBoxKitConsentStatus.accepted();
    }
    return AppBoxKitConsentStatus.acceptedOutdatedVersion(latest.documentVersion);
  }

  /// Records acceptance of [document] on this track and emits the new status.
  ///
  /// [method] defaults to [AppBoxKitConsentMethod.explicitTap]; pass
  /// [AppBoxKitConsentMethod.implicitContinue] to record implicit consent (e.g. for a
  /// document that does not require explicit acceptance).
  Future<void> accept(
    AppBoxKitComplianceDocument document, {
    required String appVersion,
    AppBoxKitConsentMethod method = AppBoxKitConsentMethod.explicitTap,
    DateTime? at,
  }) async {
    await _store.record(AppBoxKitConsentRecord(
      documentId: document.id,
      documentVersion: document.version,
      userId: userId,
      acceptedAt: at ?? DateTime.now(),
      method: method,
      appVersion: appVersion,
    ));
    await _emit(document);
  }

  /// Records a withdrawal of [document] on this track and emits the new status.
  Future<void> withdraw(
    AppBoxKitComplianceDocument document, {
    required String appVersion,
    DateTime? at,
  }) async {
    await _store.withdraw(
      documentId: document.id,
      documentVersion: document.version,
      appVersion: appVersion,
      userId: userId,
      at: at,
    );
    await _emit(document);
  }

  /// The documents in the registry that require explicit acceptance and whose
  /// current version is not satisfied on this track, in registry order.
  Future<List<AppBoxKitComplianceDocument>> outstandingDocuments() async {
    final outstanding = <AppBoxKitComplianceDocument>[];
    for (final document in _registry.currentDocuments) {
      if (!document.requiresExplicitAcceptance) continue;
      final status = await statusFor(document);
      if (!status.isSatisfied) outstanding.add(document);
    }
    return List<AppBoxKitComplianceDocument>.unmodifiable(outstanding);
  }

  /// Releases the status-change stream. Call when disposing the service.
  Future<void> dispose() => _changes.close();

  Future<void> _emit(AppBoxKitComplianceDocument document) async {
    if (_changes.isClosed) return;
    _changes.add(AppBoxKitConsentStatusChange(
        document: document, status: await statusFor(document)));
  }
}
