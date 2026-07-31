import 'dart:async';

import 'package:flutter/foundation.dart';

import 'kit_compliance_document.dart';
import 'kit_compliance_registry.dart';
import 'kit_consent_record.dart';
import 'kit_consent_status.dart';
import 'kit_consent_store.dart';

/// A status change emitted on [KitConsentService.statusChanges].
@immutable
final class KitConsentStatusChange {
  const KitConsentStatusChange({required this.document, required this.status});

  final KitComplianceDocument document;
  final KitConsentStatus status;

  @override
  bool operator ==(Object other) =>
      other is KitConsentStatusChange &&
      document == other.document &&
      status == other.status;

  @override
  int get hashCode => Object.hash(document, status);

  @override
  String toString() => 'KitConsentStatusChange(${document.id}: $status)';
}

/// Reads and mutates consent for a single user track — the [userId] supplied at
/// construction (null = the anonymous track) — on top of a [KitConsentStore]
/// and a [KitComplianceRegistry].
///
/// [accept] and [withdraw] write to the store and push a
/// [KitConsentStatusChange] on the broadcast [statusChanges] stream. Call
/// [dispose] to release that stream.
class KitConsentService {
  KitConsentService({
    required KitConsentStore store,
    required KitComplianceRegistry registry,
    this.userId,
  })  : _store = store,
        _registry = registry;

  final KitConsentStore _store;
  final KitComplianceRegistry _registry;

  /// The user track this service reads and writes (null = anonymous).
  final String? userId;

  final StreamController<KitConsentStatusChange> _changes =
      StreamController<KitConsentStatusChange>.broadcast();

  /// Status changes produced by [accept] / [withdraw] on this service.
  Stream<KitConsentStatusChange> get statusChanges => _changes.stream;

  /// The consent status of [document] on this service's track.
  ///
  /// A document that does not require explicit acceptance is always
  /// [KitConsentNotRequired], irrespective of any implicit records.
  Future<KitConsentStatus> statusFor(KitComplianceDocument document) async {
    if (!document.requiresExplicitAcceptance) {
      return const KitConsentStatus.notRequired();
    }
    final latest = await _store.latestFor(document.id, userId: userId);
    if (latest == null) return const KitConsentStatus.neverAccepted();
    if (latest.method == KitConsentMethod.withdrawn) {
      return const KitConsentStatus.withdrawn();
    }
    if (latest.documentVersion == document.version) {
      return const KitConsentStatus.accepted();
    }
    return KitConsentStatus.acceptedOutdatedVersion(latest.documentVersion);
  }

  /// Records acceptance of [document] on this track and emits the new status.
  ///
  /// [method] defaults to [KitConsentMethod.explicitTap]; pass
  /// [KitConsentMethod.implicitContinue] to record implicit consent (e.g. for a
  /// document that does not require explicit acceptance).
  Future<void> accept(
    KitComplianceDocument document, {
    required String appVersion,
    KitConsentMethod method = KitConsentMethod.explicitTap,
    DateTime? at,
  }) async {
    await _store.record(KitConsentRecord(
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
    KitComplianceDocument document, {
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
  Future<List<KitComplianceDocument>> outstandingDocuments() async {
    final outstanding = <KitComplianceDocument>[];
    for (final document in _registry.currentDocuments) {
      if (!document.requiresExplicitAcceptance) continue;
      final status = await statusFor(document);
      if (!status.isSatisfied) outstanding.add(document);
    }
    return List<KitComplianceDocument>.unmodifiable(outstanding);
  }

  /// Releases the status-change stream. Call when disposing the service.
  Future<void> dispose() => _changes.close();

  Future<void> _emit(KitComplianceDocument document) async {
    if (_changes.isClosed) return;
    _changes.add(KitConsentStatusChange(
        document: document, status: await statusFor(document)));
  }
}
